import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

const releaseRepository = 'yaotutu/pi-muse-flutter';
const latestReleaseUrl =
    'https://api.github.com/repos/$releaseRepository/releases/latest';
const universalApkName = 'app-release.apk';
const _maxApkBytes = 256 * 1024 * 1024;
const _maxReleaseBytes = 512 * 1024;
final _versionPattern = RegExp(r'^\d{1,9}\.\d{1,9}\.\d{1,9}$');
final _digestPattern = RegExp(r'^sha256:[0-9a-f]{64}$');

class AppRelease {
  const AppRelease({
    required this.version,
    required this.assetName,
    required this.size,
    required this.sha256,
    this.downloadUrl,
  });

  final String version;
  final String assetName;
  final int size;
  final String sha256;
  final String? downloadUrl;
}

class ReleaseCheckException implements Exception {
  const ReleaseCheckException(this.message);
  final String message;
}

List<int> _versionParts(String version) {
  if (!_versionPattern.hasMatch(version)) {
    throw const ReleaseCheckException('版本号格式不受支持');
  }
  return version.split('.').map(int.parse).toList();
}

bool isNewerVersion(String candidate, String installed) {
  final next = _versionParts(candidate);
  final current = _versionParts(installed);
  for (var index = 0; index < next.length; index++) {
    if (next[index] != current[index]) return next[index] > current[index];
  }
  return false;
}

const latestApkDownloadUrl =
    'https://github.com/$releaseRepository/releases/latest/download/$universalApkName';

AppRelease parseRelease(Object? value, {Abi? abi, Uri? serverOrigin}) {
  if (value is! Map<String, dynamic>) {
    throw const ReleaseCheckException('发布信息格式不正确');
  }
  final tag = value['tag_name'];
  if (value['draft'] != false ||
      value['prerelease'] != false ||
      tag is! String ||
      !tag.startsWith('v') ||
      !_versionPattern.hasMatch(tag.substring(1))) {
    throw const ReleaseCheckException('当前发布不是受支持的正式版本');
  }
  final assets = value['assets'];
  if (assets is! List) {
    throw const ReleaseCheckException('发布信息缺少有效安装包');
  }
  final preferred = switch (abi) {
    Abi.androidArm64 => 'app-arm64-v8a-release.apk',
    Abi.androidArm => 'app-armeabi-v7a-release.apk',
    Abi.androidX64 => 'app-x86_64-release.apk',
    _ => universalApkName,
  };
  final apkAssets = assets.whereType<Map<String, dynamic>>();
  var matches = apkAssets.where((asset) => asset['name'] == preferred);
  if (matches.isEmpty && preferred != universalApkName) {
    matches = apkAssets.where((asset) => asset['name'] == universalApkName);
  }
  if (matches.length != 1) {
    throw const ReleaseCheckException('正式版本没有唯一的 Android 安装包');
  }
  final asset = matches.single;
  final assetName = asset['name'] as String;
  final size = asset['size'];
  final digest = asset['digest'];
  final mirrorPath = '/updates/android/apk/$tag/$assetName';
  final expectedUrl = serverOrigin != null
      ? mirrorPath
      : 'https://github.com/$releaseRepository/releases/download/$tag/$assetName';
  if (asset['browser_download_url'] != expectedUrl) {
    throw const ReleaseCheckException('安装包不属于官方发布地址');
  }
  if (size is! int ||
      size <= 0 ||
      size > _maxApkBytes ||
      digest is! String ||
      !_digestPattern.hasMatch(digest)) {
    throw const ReleaseCheckException('安装包大小或校验值无效');
  }
  return AppRelease(
    version: tag.substring(1),
    assetName: assetName,
    size: size,
    sha256: digest.substring(7),
    downloadUrl: serverOrigin
        ?.replace(path: mirrorPath, query: null, fragment: null)
        .toString(),
  );
}

/// 已连接 Pi Muse 服务端时优先走同源镜像；未连接服务端时回退直连 GitHub。
Future<AppRelease?> getLatestRelease(
  HttpClient client, {
  Uri? serverOrigin,
  bool manual = false,
}) async {
  try {
    if (serverOrigin != null) {
      return await _readServerRelease(
        client,
        serverOrigin,
        manual: manual,
      ).timeout(const Duration(seconds: 20));
    }
    return await _readLatestRelease(
      client,
    ).timeout(const Duration(seconds: 20));
  } on TimeoutException {
    throw ReleaseCheckException(
      serverOrigin != null
          ? '连接当前服务端检查更新超时，请稍后重试'
          : '检查更新超时，请稍后重试',
    );
  } on IOException {
    throw ReleaseCheckException(
      serverOrigin != null
          ? '无法连接当前服务端检查更新，请确认服务在线后重试'
          : '无法连接 GitHub，请稍后重试',
    );
  } on FormatException {
    throw const ReleaseCheckException('发布信息格式不正确');
  }
}

Future<AppRelease?> _readServerRelease(
  HttpClient client,
  Uri serverOrigin, {
  required bool manual,
}) async {
  if (manual) {
    try {
      final refresh = await client
          .postUrl(
            serverOrigin.replace(
              path: '/updates/android/refresh',
              query: null,
              fragment: null,
            ),
          )
          .timeout(const Duration(seconds: 3));
      refresh.followRedirects = false;
      final refreshResp =
          await refresh.close().timeout(const Duration(seconds: 3));
      await refreshResp.drain<void>();
    } catch (_) {
      // 刷新通知失败不阻断读取已镜像的版本清单。
    }
  }
  final request = await client.getUrl(
    serverOrigin.replace(
      path: '/updates/android/latest',
      query: null,
      fragment: null,
    ),
  );
  request.followRedirects = false;
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  final response = await request.close();
  if (response.statusCode == HttpStatus.serviceUnavailable) {
    await response.drain<void>();
    throw const ReleaseCheckException('服务端正在同步最新版本安装包，请稍后再点检查更新');
  }
  if (response.statusCode != HttpStatus.ok) {
    await response.drain<void>();
    throw const ReleaseCheckException('服务端更新渠道暂不可用，请稍后重试');
  }
  final decoded = await _readJsonBody(response);
  return parseRelease(
    decoded,
    abi: Abi.current(),
    serverOrigin: serverOrigin,
  );
}

Future<AppRelease?> _readLatestRelease(HttpClient client) async {
  final request = await client.getUrl(Uri.parse(latestReleaseUrl));
  request.followRedirects = false;
  request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
  request.headers.set(HttpHeaders.userAgentHeader, 'pi-muse-flutter');
  final response = await request.close();
  if (response.statusCode == HttpStatus.notFound) {
    await response.drain<void>();
    return null;
  }
  if (response.statusCode == HttpStatus.forbidden ||
      response.statusCode == HttpStatus.tooManyRequests) {
    await response.drain<void>();
    throw const ReleaseCheckException('GitHub 接口请求受限，请连接服务端后重试或稍后再试');
  }
  if (response.statusCode != HttpStatus.ok) {
    await response.drain<void>();
    throw const ReleaseCheckException('GitHub 更新服务暂不可用');
  }
  final decoded = await _readJsonBody(response);
  return parseRelease(decoded, abi: Abi.current());
}

Future<Object?> _readJsonBody(HttpClientResponse response) async {
  final body = BytesBuilder(copy: false);
  await for (final chunk in response) {
    if (body.length + chunk.length > _maxReleaseBytes) {
      throw const ReleaseCheckException('发布信息过大');
    }
    body.add(chunk);
  }
  return jsonDecode(utf8.decode(body.takeBytes()));
}
