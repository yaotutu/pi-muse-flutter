import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/sms_sync_page.dart';

const _historyIdle = {
  'permission': false,
  'busy': false,
  'retryReady': false,
  'state': 'idle',
  'accepted': 0,
  'skipped': 0,
  'failed': 0,
};

void main() {
  const channel = MethodChannel('pi_muse/sms_sync');
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('requires disclosure and permission before enabling', (
    tester,
  ) async {
    var enableCalls = 0;
    var settingsCalls = 0;
    var permission = false;
    var enabled = false;
    Completer<Map<String, Object?>>? delayedStatus;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'historyStatus') return _historyIdle;
      if (call.method == 'enable') {
        enableCalls++;
        enabled = permission;
        return enabled;
      }
      if (call.method == 'openAppSettings') {
        settingsCalls++;
        return null;
      }
      expect(call.method, 'status');
      if (delayedStatus != null) {
        final pending = delayedStatus!;
        delayedStatus = null;
        return pending.future;
      }
      return {'enabled': enabled, 'permission': permission, 'pending': 0};
    });
    await tester.pumpWidget(
      const MaterialApp(home: SmsSyncPage(connectionUsesHttp: true)),
    );
    await tester.pumpAndSettle();
    final toggle = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.textContaining('传输时未加密'), findsWidgets);
    expect(enableCalls, 0);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(enableCalls, 1);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.textContaining('允许受限设置'), findsOneWidget);
    final openSettings = find.text('打开应用设置');
    await tester.tap(openSettings);
    await tester.pumpAndSettle();
    expect(settingsCalls, 1);
    expect(enableCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(openSettings, findsOneWidget);

    final beforeReturning = Completer<Map<String, Object?>>();
    delayedStatus = beforeReturning;
    await tester.pump(const Duration(seconds: 2));
    expect(delayedStatus, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    permission = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    beforeReturning.complete({'enabled': false, 'permission': false});
    await tester.pumpAndSettle();
    expect(openSettings, findsNothing);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(enableCalls, 1);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(enableCalls, 2);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.text('仅同步开启后收到的新短信'), findsOneWidget);
    expect(find.textContaining('正在等待新短信'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    permission = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(openSettings, findsOneWidget);
    expect(find.text('重新授权短信权限'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('shows queued count and supports retry after server rejection', (
    tester,
  ) async {
    var block = 'disabled';
    var retryCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'historyStatus') return _historyIdle;
      if (call.method == 'retry') {
        retryCalls++;
        block = 'idle';
        return null;
      }
      expect(call.method, 'status');
      return {
        'enabled': true,
        'permission': true,
        'pending': 2,
        'canRetry': 1,
        'status': block,
      };
    });
    await tester.pumpWidget(
      const MaterialApp(home: SmsSyncPage(connectionUsesHttp: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('待同步 2 条'), findsOneWidget);
    expect(find.textContaining('服务器的信息后台已关闭'), findsOneWidget);
    expect(find.textContaining('短信已保存在本机'), findsOneWidget);
    block = 'paused';
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('待同步 2 条'), findsOneWidget);
    expect(find.textContaining('短信已保存在本机'), findsOneWidget);
    expect(find.textContaining('服务器恢复接收后'), findsOneWidget);
    await tester.tap(find.text('立即同步'));
    await tester.pumpAndSettle();
    expect(retryCalls, 1);
    expect(find.textContaining('服务器恢复接收后'), findsNothing);
    block = 'auth';
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('连接已失效'), findsOneWidget);
    await tester.tap(find.text('立即同步'));
    await tester.pumpAndSettle();
    expect(retryCalls, 1);
  });

  testWidgets('history requires separate permission and explicit upload', (
    tester,
  ) async {
    var historyPermission = false;
    var historyState = 'idle';
    var imports = 0;
    var pauses = 0;
    var permissionRequests = 0;
    var settingsCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'status':
          return {'enabled': false, 'permission': true, 'pending': 0};
        case 'historyStatus':
          return {
            ..._historyIdle,
            'permission': historyPermission,
            'state': historyState,
            'busy': historyState == 'running',
            'accepted': historyState == 'idle' ? 0 : 7,
            'skipped': historyState == 'idle' ? 0 : 2,
            'failed': historyState == 'idle' ? 0 : 1,
          };
        case 'requestHistoryPermission':
          permissionRequests++;
          return historyPermission;
        case 'openAppSettings':
          settingsCalls++;
          return null;
        case 'startHistory':
          imports++;
          expect(historyPermission, isTrue);
          historyState = 'running';
          return null;
        case 'pauseHistory':
          pauses++;
          historyState = 'paused';
          return null;
      }
      throw StateError('Unexpected method ${call.method}');
    });
    await tester.pumpWidget(
      const MaterialApp(home: SmsSyncPage(connectionUsesHttp: true)),
    );
    await tester.pumpAndSettle();
    final start = find.text('导入历史短信');
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.textContaining('短信和连接令牌在传输时未加密').hitTestable(), findsOneWidget);
    expect(find.textContaining('导入不会触发模型分析'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(permissionRequests, 0);
    expect(imports, 0);

    await tester.tap(start);
    await tester.pumpAndSettle();
    await tester.tap(find.text('去授权'));
    await tester.pumpAndSettle();
    expect(permissionRequests, 1);
    expect(imports, 0);
    final settings = find.text('打开短信权限设置');
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(settingsCalls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    historyPermission = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(settings, findsNothing);
    expect(imports, 0);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );

    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始上传'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(imports, 1);
    expect(find.text('已导入 7 条 · 已跳过 2 条 · 未能导入 1 条'), findsOneWidget);
    final pause = find.text('暂停导入');
    await tester.ensureVisible(pause);
    await tester.tap(pause);
    await tester.pumpAndSettle();
    expect(pauses, 1);
    expect(imports, 1);

    final resume = find.text('继续导入');
    await tester.ensureVisible(resume);
    await tester.tap(resume);
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续上传'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(imports, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(pauses, 2);
  });
}
