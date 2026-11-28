import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/app/workspace_page.dart';
import 'package:pi_muse_flutter/src/features/agenda/agenda.dart';
import 'package:pi_muse_flutter/src/features/appearance/appearance.dart';
import 'package:pi_muse_flutter/src/features/chat/chat_controller.dart';
import 'package:pi_muse_flutter/src/network/api.dart';
import 'package:pi_muse_flutter/src/shared/agenda_receipt.dart';

import '../../support/agenda_test_api.dart';

/// 生成一条测试事项。
Map<String, dynamic> agendaItem(
  String id,
  String title, {
  String? notes,
  String? schedule,
}) => {
  'id': id,
  'title': title,
  'notes': notes,
  'schedule': schedule == null
      ? null
      : {'type': 'date', 'start': schedule, 'timeZone': 'Asia/Shanghai'},
  'due': null,
  'pinnedAt': null,
  'completedAt': null,
  'createdAt': '2026-03-01T00:00:00Z',
  'updatedAt': '2026-03-01T00:00:00Z',
  'reminders': <Json>[],
};

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

  testWidgets(
    'reminder editing preserves relative rules and supports dismissal',
    (tester) async {
      tester.view.physicalSize = const Size(780, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final year = DateTime.now().year + 1;
      final api = AgendaTestApi()
        ..items = [
          {
            'id': 'item',
            'title': '交报告',
            'due': {'type': 'time', 'value': '$year-12-01T10:00:00Z'},
            'reminders': [
              {
                'id': 'relative',
                'kind': 'before_due',
                'offsetMinutes': 30,
                'fireAt': '$year-12-01T09:30:00Z',
                'status': 'pending',
              },
              {
                'id': 'absolute',
                'kind': 'absolute',
                'fireAt': '$year-12-01T09:00:00Z',
                'status': 'pending',
              },
            ],
          },
        ];
      final agenda = AgendaController(
        client: AgendaClient(api),
        events: const Stream.empty(),
      );
      addTearDown(agenda.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AgendaItemPage(agenda: agenda, itemId: 'item'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('取消提醒'), findsNWidgets(2));
      final edit = find.byTooltip('修改提醒');
      expect(edit, findsOneWidget);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(api.agendaWrites, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('phone agenda leaves room for search when the keyboard opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = AgendaTestApi()..items = [agendaItem('item', '取快递')];
    final chat = ChatController(api, () => api)..synchronized = true;
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
    await tester.tap(find.text('日程'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    final listBounds = tester.getRect(find.byType(ListView));
    expect(
      listBounds.bottom,
      closeTo(tester.getTopLeft(find.byType(NavigationBar)).dy, 1),
    );

    await tester.tap(find.byTooltip('搜索事项'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.text('取快递').hitTestable(), findsOneWidget);
    await tester.enterText(find.byType(TextField), '快递');
    await tester.tap(find.byTooltip('应用搜索'));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(api.agendaQueries.any((query) => query?['q'] == '快递'), isTrue);
    expect(find.byType(GridView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing item shows a retry instead of a blank edit form', (
    tester,
  ) async {
    final api = AgendaTestApi();
    final agenda = AgendaController(
      client: AgendaClient(api),
      events: const Stream.empty(),
    );
    addTearDown(agenda.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AgendaItemPage(agenda: agenda, itemId: 'item'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('事项不存在或已被删除'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('保存'), findsNothing);
    expect(agenda.notice, isNull);
    api.items = [agendaItem('item', '交报告')];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('交报告'), findsOneWidget);
    expect(find.text('保存').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'wide landscape splits the agenda into a calendar pane and an independent list pane',
    (tester) async {
      // TB300FU 横屏：1280x800 物理像素，密度 213，约 962x601 dp。
      tester.view.physicalSize = const Size(962, 601);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = AgendaTestApi()
        ..items = [
          agendaItem('item', '取快递', schedule: '2026-03-08'),
          for (var index = 0; index < 12; index++)
            agendaItem('item-$index', '待办 $index'),
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
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('日程'),
        ),
      );
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final monthTitle = find.text('${now.year}年${now.month}月');
      final firstItem = find.text('取快递');
      expect(monthTitle, findsOneWidget);
      expect(firstItem, findsOneWidget);

      // 月历在左栏，事项列表在右栏。
      expect(
        tester.getTopLeft(monthTitle).dx,
        lessThan(tester.getTopLeft(firstItem).dx),
      );
      // 事项行和当月日期都在可视范围内。
      expect(firstItem.hitTestable(), findsOneWidget);
      expect(find.text('15').hitTestable(), findsOneWidget);

      // 列表独立滚动，左侧月历不动。
      await tester.drag(firstItem, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(firstItem.hitTestable(), findsNothing);
      expect(monthTitle.hitTestable(), findsOneWidget);
      expect(find.text('15').hitTestable(), findsOneWidget);

      // 搜索框与列表同栏。
      await tester.tap(find.byTooltip('搜索事项'));
      await tester.pumpAndSettle();
      final search = find.byType(TextField);
      expect(search, findsOneWidget);
      expect(
        tester.getTopLeft(search).dx,
        greaterThan(tester.getTopLeft(monthTitle).dx),
      );

      // 竖屏宽窗口不分栏，保持单列。
      tester.view.physicalSize = const Size(800, 1200);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('agenda-pane-divider')), findsNothing);
      expect(
        tester.getTopLeft(monthTitle).dy,
        lessThan(tester.getTopLeft(find.text('未完成')).dy),
      );
    },
  );

  testWidgets(
    'wide landscape keeps the item detail actions reachable and the phone layout intact',
    (tester) async {
      tester.view.physicalSize = const Size(962, 601);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = AgendaTestApi()
        ..items = [
          agendaItem('item', '交报告', notes: '写完再发', schedule: '2026-12-01'),
        ];
      final agenda = AgendaController(
        client: AgendaClient(api),
        events: const Stream.empty(),
      );
      addTearDown(agenda.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AgendaItemPage(agenda: agenda, itemId: 'item'),
        ),
      );
      await tester.pumpAndSettle();

      final title = find.widgetWithText(TextField, '标题');
      final schedule = find.text('安排时间');
      expect(title, findsOneWidget);
      expect(schedule, findsOneWidget);
      expect(find.byKey(const Key('agenda-item-pane-divider')), findsOneWidget);
      // 宽横屏下标题在左，时间设置在右。
      expect(
        tester.getTopLeft(title).dx,
        lessThan(tester.getTopLeft(schedule).dx),
      );
      // 保存与标记完成固定在底部，不用滚动就能点到。
      expect(find.text('保存').hitTestable(), findsOneWidget);
      expect(find.text('标记完成').hitTestable(), findsOneWidget);

      // 完成动作照旧写回服务端。
      await tester.tap(find.text('标记完成'));
      await tester.pumpAndSettle();
      expect(api.agendaWrites, hasLength(1));
      expect(api.agendaWrites.first.$1, '/api/agenda/items/item');
      expect(api.agendaWrites.first.$2?['completed'], isTrue);
      expect(find.text('重新打开'), findsOneWidget);

      // 竖屏恢复单列表单，弹出键盘也能从底部保存。
      addTearDown(tester.view.resetViewInsets);
      tester.view.physicalSize = const Size(390, 780);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('agenda-item-pane-divider')), findsNothing);
      expect(
        tester.getTopLeft(title).dy,
        lessThan(tester.getTopLeft(schedule).dy),
      );
      await tester.tap(title);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.text('保存').hitTestable(), findsOneWidget);
      expect(find.text('重新打开').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
