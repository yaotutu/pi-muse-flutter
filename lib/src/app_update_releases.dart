import 'dart:async';
import 'dart:convert';
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
    required this.size,
    required this.sha256,
  });

  final String version;
  final int size;
  final String sha256;
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

AppRelease parseRelease(Object? value) {
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
  final matches = assets.whereType<Map<String, dynamic>>().where(
    (asset) => asset['name'] == universalApkName,
  );
  if (matches.length != 1) {
    throw const ReleaseCheckException('正式版本没有唯一的 Android 安装包');
  }
  final asset = matches.single;
  final size = asset['size'];
  final digest = asset['digest'];
  final officialUrl =
      'https://github.com/$releaseRepository/releases/download/$tag/$universalApkName';
  if (asset['browser_download_url'] != officialUrl) {
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
    size: size,
    sha256: digest.substring(7),
  );
}

/// 404 表示手机当前无法读取正式发布。其他错误保留重试入口。
Future<AppRelease?> getLatestRelease(HttpClient client) async {
  try {
    return await _readLatestRelease(
      client,
    ).timeout(const Duration(seconds: 20));
  } on TimeoutException {
    throw const ReleaseCheckException('检查更新超时，请稍后重试');
  } on IOException {
    throw const ReleaseCheckException('无法连接 GitHub，请稍后重试');
  } on FormatException {
    throw const ReleaseCheckException('发布信息格式不正确');
  }
}

Future<AppRelease?> _readLatestRelease(HttpClient client) async {
  final request = await client.getUrl(Uri.parse(latestReleaseUrl));
  request.followRedirects = false;
  request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
  final response = await request.close();
  if (response.statusCode == HttpStatus.notFound) return null;
  if (response.statusCode != HttpStatus.ok) {
    throw const ReleaseCheckException('GitHub 更新服务暂不可用');
  }
  final body = BytesBuilder(copy: false);
  await for (final chunk in response) {
    if (body.length + chunk.length > _maxReleaseBytes) {
      throw const ReleaseCheckException('发布信息过大');
    }
    body.add(chunk);
  }
  return parseRelease(jsonDecode(utf8.decode(body.takeBytes())));
}
