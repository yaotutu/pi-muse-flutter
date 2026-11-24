import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/sms_sync_page.dart';

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
}
