import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_update_releases.dart';

class AppUpdateBridge {
  static const _channel = MethodChannel('pi_muse/app_update');

  static Future<({String version, bool supported})?> device() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final data = await _channel.invokeMapMethod<String, Object?>('device');
    final version = data?['version'];
    if (version is! String || version.isEmpty) return null;
    return (version: version, supported: data?['supported'] == true);
  }

  static Future<bool> download(
    AppRelease release,
    ValueChanged<int> progress,
  ) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress' && call.arguments is int) {
        progress(call.arguments as int);
      }
    });
    try {
      return await _channel.invokeMethod<bool>('download', {
            'version': release.version,
            'assetName': release.assetName,
            'size': release.size,
            'sha256': release.sha256,
            'downloadUrl': ?release.downloadUrl,
          }) ==
          true;
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  static Future<bool> install() async =>
      await _channel.invokeMethod<bool>('install') == true;

  static Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  static Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}
