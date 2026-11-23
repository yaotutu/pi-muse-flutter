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
    var permission = false;
    var enabled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'enable') {
        enableCalls++;
        enabled = permission;
        return enabled;
      }
      expect(call.method, 'status');
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
    expect(find.textContaining('请在 Android 应用权限中'), findsOneWidget);

    permission = true;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(enableCalls, 2);
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
    expect(find.textContaining('服务器已关闭短信处理'), findsOneWidget);
    await tester.tap(find.text('立即同步'));
    await tester.pumpAndSettle();
    expect(retryCalls, 1);
    expect(find.textContaining('服务器已关闭短信处理'), findsNothing);
    block = 'auth';
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('连接已失效'), findsOneWidget);
    await tester.tap(find.text('立即同步'));
    await tester.pumpAndSettle();
    expect(retryCalls, 1);
  });
}
