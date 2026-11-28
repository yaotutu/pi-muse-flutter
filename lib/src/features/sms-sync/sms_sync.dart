import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SmsSync {
  static const _channel = MethodChannel('pi_muse/sms_sync');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<Map<String, Object?>> status() async =>
      (await _channel.invokeMapMethod<String, Object?>('status'))!;

  static Future<bool> setEnabled(bool enabled) async =>
      (await _channel.invokeMethod<bool>(enabled ? 'enable' : 'disable'))!;

  static Future<void> retry() => _channel.invokeMethod<void>('retry');

  static Future<void> openAppSettings() =>
      _channel.invokeMethod<void>('openAppSettings');

  static Future<SmsHistoryStatus> historyStatus() async {
    final data = (await _channel.invokeMapMethod<String, Object?>(
      'historyStatus',
    ))!;
    return SmsHistoryStatus(
      permission: data['permission'] as bool,
      busy: data['busy'] as bool,
      retryReady: data['retryReady'] as bool,
      state: data['state'] as String,
      accepted: data['accepted'] as int,
      skipped: data['skipped'] as int,
      failed: data['failed'] as int,
    );
  }

  static Future<bool> requestHistoryPermission() async =>
      (await _channel.invokeMethod<bool>('requestHistoryPermission'))!;

  static Future<void> startHistory() =>
      _channel.invokeMethod<void>('startHistory');

  static Future<void> pauseHistory() =>
      _channel.invokeMethod<void>('pauseHistory');

  static Future<void> resume({bool connectionChanged = false}) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(
        connectionChanged ? 'connectionChanged' : 'resume',
      );
    } on PlatformException {
      // 连接已保存，本机短信错误在设置页显示。
    } on MissingPluginException {
      // 非原生运行环境没有后台短信队列。
    }
  }
}

class SmsHistoryStatus {
  const SmsHistoryStatus({
    required this.permission,
    required this.busy,
    required this.retryReady,
    required this.state,
    required this.accepted,
    required this.skipped,
    required this.failed,
  });

  final bool permission;
  final bool busy;
  final bool retryReady;
  final String state;
  final int accepted;
  final int skipped;
  final int failed;
}
