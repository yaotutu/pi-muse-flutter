import 'dart:async';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_muse_flutter/src/app_update.dart';
import 'package:pi_muse_flutter/src/app_update_releases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pi_muse/app_update');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final checksum = List.filled(64, 'a').join();
  final asset = <String, Object>{
    'name': 'app-release.apk',
    'size': 1024,
    'digest': 'sha256:$checksum',
    'browser_download_url':
        'https://github.com/$releaseRepository/releases/download/v0.1.2/app-release.apk',
  };
  final metadata = <String, Object>{
    'draft': false,
    'prerelease': false,
    'tag_name': 'v0.1.2',
    'assets': [asset],
  };
  final release = parseRelease(metadata);
  final invalid = throwsA(isA<ReleaseCheckException>());
  final splitChecksum = List.filled(64, 'b').join();
  const splitNames = {
    Abi.androidArm64: 'app-arm64-v8a-release.apk',
    Abi.androidArm: 'app-armeabi-v7a-release.apk',
    Abi.androidX64: 'app-x86_64-release.apk',
  };
  final splitAssets = {
    for (final entry in splitNames.entries)
      entry.key: <String, Object>{
        'name': entry.value,
        'size': 512,
        'digest': 'sha256:$splitChecksum',
        'browser_download_url':
            'https://github.com/$releaseRepository/releases/download/v0.1.2/${entry.value}',
      },
  };
  final allApks = {
    ...metadata,
    'assets': [asset, ...splitAssets.values],
  };
  final splitRelease = parseRelease(allApks, abi: Abi.androidArm64);

  test('按三段数字比较版本', () {
    expect(isNewerVersion('0.1.10', '0.1.9'), isTrue);
    expect(isNewerVersion('1.0.0', '0.9.9'), isTrue);
    expect(isNewerVersion('0.1.1', '0.1.1'), isFalse);
    expect(isNewerVersion('0.1.0', '0.1.1'), isFalse);
    expect(() => isNewerVersion('0.1', '0.1.0'), invalid);
  });

  test('只接受官方正式版本的唯一通用包和有效摘要', () {
    expect(release.version, '0.1.2');
    expect(release.size, 1024);
    expect(release.sha256, checksum);
    expect(() => parseRelease({...metadata, 'draft': true}), invalid);
    expect(() => parseRelease({...metadata, 'prerelease': true}), invalid);
    expect(() => parseRelease({...metadata, 'tag_name': '0.1.2'}), invalid);
    expect(() => parseRelease({...metadata, 'assets': []}), invalid);
    expect(
      () => parseRelease({
        ...metadata,
        'assets': [asset, asset],
      }),
      invalid,
    );
    for (final replacement in [
      {'browser_download_url': 'https://elsewhere.example/app-release.apk'},
      {'size': 257 * 1024 * 1024},
      {'digest': null},
      {'digest': 'sha256:123'},
    ]) {
      expect(
        () => parseRelease({
          ...metadata,
          'assets': [
            {...asset, ...replacement},
          ],
        }),
        invalid,
      );
    }
  });

  test('优先使用当前 Android 进程架构的安装包', () {
    for (final entry in splitNames.entries) {
      final selected = parseRelease(allApks, abi: entry.key);
      expect(selected.assetName, entry.value);
      expect(selected.size, 512);
      expect(selected.sha256, splitChecksum);
    }
  });

  test('旧发布、缺少匹配包或架构不受支持时使用通用包', () {
    final otherAbiOnly = {
      ...metadata,
      'assets': [asset, splitAssets[Abi.androidX64]],
    };
    for (final selected in [
      parseRelease(metadata, abi: Abi.androidArm64),
      parseRelease(otherAbiOnly, abi: Abi.androidArm64),
      parseRelease(allApks, abi: Abi.androidIA32),
      parseRelease(allApks),
    ]) {
      expect(selected.assetName, universalApkName);
      expect(selected.size, 1024);
      expect(selected.sha256, checksum);
    }
  });

  test('匹配包重复或元数据无效时检查失败', () {
    final split = splitAssets[Abi.androidArm64]!;
    for (final splits in [
      [split, split],
      [
        {...split, 'browser_download_url': asset['browser_download_url']},
      ],
      [
        {...split, 'digest': 'sha256:123'},
      ],
      [
        {...split, 'size': 0},
      ],
    ]) {
      expect(
        () => parseRelease({
          ...metadata,
          'assets': [asset, ...splits],
        }, abi: Abi.androidArm64),
        invalid,
      );
    }
  });

  group('Android 更新流程', () {
    const device = {'version': '0.1.0', 'supported': true};
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });

    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test('显示 Android 版本名，尚无公开发布时让用户再次检查', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => device);
      final controller = AppUpdateController(lookupRelease: (_) async => null);
      addTearDown(controller.dispose);
      controller.setForeground(true);
      await flush();
      expect(controller.currentVersion, '0.1.0');
      expect(controller.status, AppUpdateStatus.unpublished);
    });

    test('进度可读，切到后台时等回到前台才要求安装授权', () async {
      final download = Completer<bool>();
      final calls = <String>[];
      var permitted = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'device' => device,
          'download' => download.future,
          'install' => permitted,
          'openInstallSettings' => null,
          _ => throw StateError('Unexpected method ${call.method}'),
        };
      });
      final controller = AppUpdateController(
        lookupRelease: (_) async => release,
      );
      addTearDown(controller.dispose);
      controller.setForeground(true);
      await flush();
      expect(controller.status, AppUpdateStatus.downloading);
      unawaited(
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('progress', 256),
          ),
          (_) {},
        ),
      );
      await flush();
      expect(controller.bytesWritten, 256);
      controller.setForeground(false);
      download.complete(true);
      await flush();
      expect(controller.status, AppUpdateStatus.ready);
      expect(calls, ['device', 'download']);
      controller.setForeground(true);
      await flush();
      expect(controller.status, AppUpdateStatus.permission);
      await controller.openInstallSettings();
      permitted = true;
      await controller.install();
      expect(controller.status, AppUpdateStatus.ready);
      expect(calls, [
        'device',
        'download',
        'install',
        'openInstallSettings',
        'install',
      ]);
    });

    test('取消后等下载收尾，迟到成功不会触发安装', () async {
      final first = Completer<bool>();
      var attempts = 0;
      var cancellations = 0;
      var installs = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'device':
            return device;
          case 'download':
            expect(call.arguments, {
              'version': '0.1.2',
              'assetName': 'app-arm64-v8a-release.apk',
              'size': 512,
              'sha256': splitChecksum,
            });
            return ++attempts == 1 ? first.future : true;
          case 'cancel':
            cancellations++;
            return null;
          case 'install':
            installs++;
            return true;
          default:
            throw StateError('Unexpected method ${call.method}');
        }
      });
      final controller = AppUpdateController(
        lookupRelease: (_) async => splitRelease,
      );
      addTearDown(controller.dispose);
      controller.setForeground(true);
      await flush();
      controller.cancel();
      await controller.retryDownload();
      expect(attempts, 1);
      expect(cancellations, 1);
      first.complete(true);
      await flush();
      expect(controller.status, AppUpdateStatus.cancelled);
      expect(installs, 0);
      await controller.retryDownload();
      await flush();
      expect(attempts, 2);
      expect(installs, 1);
    });

    test('元数据检查取消后忽略迟到版本', () async {
      final lookup = Completer<AppRelease>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return device;
      });
      final controller = AppUpdateController(
        lookupRelease: (_) => lookup.future,
      );
      addTearDown(controller.dispose);
      controller.setForeground(true);
      await flush();
      controller.cancel();
      lookup.complete(release);
      await flush();
      expect(controller.status, AppUpdateStatus.cancelled);
      expect(controller.busy, isFalse);
      expect(controller.release, isNull);
      expect(calls, ['device']);
    });

    test('调试签名显示版本且不自动检查', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {...device, 'supported': false},
      );
      final controller = AppUpdateController(
        lookupRelease: (_) async => fail('Unexpected lookup'),
      );
      addTearDown(controller.dispose);
      controller.setForeground(true);
      await flush();
      expect(controller.currentVersion, '0.1.0');
      expect(controller.status, AppUpdateStatus.unsupported);
    });
  });
}
