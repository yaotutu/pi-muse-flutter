import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/app/workspace_page.dart';
import 'package:pi_muse_flutter/src/features/appearance/appearance.dart';
import 'package:pi_muse_flutter/src/features/chat/chat_controller.dart';
import 'package:pi_muse_flutter/src/network/api.dart';
import 'package:pi_muse_flutter/src/shared/agenda_receipt.dart';

import '../../support/agenda_test_api.dart';

void main() {
  testWidgets('the agenda destination lists items and keeps the chat draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = AgendaTestApi()
      ..items = [
        {
          'id': 'item',
          'title': '取快递',
          'notes': null,
          'schedule': {
            'type': 'date',
            'start': '2026-03-08',
            'timeZone': 'Asia/Shanghai',
          },
          'due': null,
          'pinnedAt': null,
          'completedAt': null,
          'createdAt': '2026-03-01T00:00:00Z',
          'updatedAt': '2026-03-01T00:00:00Z',
          'reminders': <Json>[],
        },
      ];
    final chat = ChatController(api, () => api)..synchronized = true;
    chat.active.revision = 'revision';
    chat.active.dirty = false;
    final appearance = AppearanceSettings(
      readPalette: () async => null,
      writePalette: (_) async {},
    );
    addTearDown(chat.dispose);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspacePage(
          chat: chat,
          appearance: appearance,
          connectionBuilder: (_) => const SizedBox(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '还没写完');

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('日程'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '日程'), findsOneWidget);
    expect(find.text('取快递'), findsOneWidget);
    // 列表显示安排时间，日历上同一天标记安排。
    expect(find.textContaining('安排'), findsWidgets);
    expect(find.byIcon(Icons.event), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('聊天'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没写完'), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('日程'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('下个月').hitTestable(), findsOneWidget);
    expect(find.text('取快递').hitTestable(), findsOneWidget);
  });

  testWidgets('the receipt card opens the same agenda item', (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = AgendaTestApi()
      ..items = [
        {
          'id': 'item',
          'title': '取快递',
          'notes': '放在前台',
          'schedule': {'type': 'date', 'start': '2026-03-08'},
          'due': null,
          'pinnedAt': null,
          'completedAt': null,
          'createdAt': '2026-03-01T00:00:00Z',
          'updatedAt': '2026-03-01T00:00:00Z',
          'reminders': <Json>[],
        },
      ];
    final chat = ChatController(api, () => api)..synchronized = true;
    chat.active.revision = 'revision';
    chat.active.dirty = false;
    chat.active.history = [
      ChatMessage('message', 'assistant', '取快递已经记下了'),
      ChatMessage(
        'notification',
        'assistant',
        '事项已保存',
        agendaReceipt: const AgendaReceipt(
          id: 'receipt',
          itemId: 'item',
          title: '取快递',
          kind: 'item_created',
          when: '2026-03-08',
          timeZone: 'Asia/Shanghai',
        ),
      ),
    ];
    final appearance = AppearanceSettings(
      readPalette: () async => null,
      writePalette: (_) async {},
    );
    addTearDown(chat.dispose);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspacePage(
          chat: chat,
          appearance: appearance,
          connectionBuilder: (_) => const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('取快递已经记下了'), findsOneWidget);
    expect(find.text('事项已保存'), findsNothing);
    expect(find.text('已创建事项'), findsOneWidget);
    expect(find.text('查看事项'), findsOneWidget);

    await tester.tap(find.text('查看事项'));
    await tester.pumpAndSettle();

    // 卡片跳到日程里的同一个事项。
    expect(find.widgetWithText(AppBar, '事项详情'), findsOneWidget);
    expect(find.widgetWithText(TextField, '取快递'), findsOneWidget);
    // 外壳同时切到日程入口。
    final bar = find.byType(NavigationBar, skipOffstage: false);
    expect(tester.widget<NavigationBar>(bar).selectedIndex, 1);
  });
}
