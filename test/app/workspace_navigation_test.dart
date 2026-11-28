import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/app/workspace_page.dart';
import 'package:pi_muse_flutter/src/features/appearance/appearance.dart';
import 'package:pi_muse_flutter/src/features/chat/chat_controller.dart';
import 'package:pi_muse_flutter/src/network/api.dart';
import '../support/session_test_api.dart';

void main() {
  testWidgets(
    'switching settings preserves the chat draft and reading position',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SessionTestApi();
      final chat = ChatController(api, () => api)..synchronized = true;
      chat.active.revision = 'saved';
      chat.active.history = List.generate(
        32,
        (index) => ChatMessage('$index', 'user', 'Message $index'),
      );
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
      final scrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(300);
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('外观'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('聊天'));
      await tester.pumpAndSettle();
      expect(find.text('还没写完'), findsOneWidget);
      expect(
        tester.state<ScrollableState>(scrollable).position,
        same(position),
      );
      expect(position.pixels, closeTo(300, 1));
    },
  );

  testWidgets(
    'manage topics from the drawer and re-confirm a changed task list',
    (tester) async {
      final api = SessionTestApi();
      final chat = ChatController(api, () => api)..synchronized = true;
      final appearance = AppearanceSettings(
        readPalette: () async => null,
        writePalette: (_) async {},
      );
      addTearDown(chat.dispose);
      addTearDown(appearance.dispose);
      await chat.refreshDirectory();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspacePage(
            chat: chat,
            appearance: appearance,
            connectionBuilder: (_) => const SizedBox(),
          ),
        ),
      );
      final menuButton = find.byTooltip('打开导航菜单');
      final drawer = find.byType(Drawer);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: drawer, matching: find.text('计划')));
      await tester.pumpAndSettle();
      expect(chat.activeId, 'topic');
      expect(drawer, findsNothing);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      expect(find.byTooltip('更多操作：默认会话'), findsNothing);
      Future<void> openAction(String title, String action) async {
        final menu = find.byWidgetPredicate(
          (widget) =>
              widget is PopupMenuButton && widget.tooltip == '更多操作：$title',
        );
        expect(menu, findsOneWidget);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
      }

      await openAction('计划', '重命名');
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog).last,
          matching: find.byType(TextField),
        ),
        '新计划',
      );
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(drawer, findsOneWidget);
      expect(
        find.descendant(of: drawer, matching: find.text('新计划')),
        findsOneWidget,
      );
      await openAction('新计划', '删除');
      expect(find.text('定时任务：任务 1'), findsOneWidget);
      expect(find.text('网页监控：更新监控'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(api.deletes, isEmpty);
      await openAction('新计划', '删除');
      expect(find.text('定时任务：任务 2'), findsOneWidget);
      await tester.tap(find.text('保留并转到默认会话'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '删除会话'));
      await tester.pumpAndSettle();
      expect(find.text('任务或监控已变化，请核对新清单后再确认。'), findsOneWidget);
      expect(find.text('定时任务：任务 3'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '删除会话'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('保留并转到默认会话'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '删除会话'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '继续删除'))
            .onPressed,
        isNull,
      );
      api.finalDelete.complete({
        'ok': true,
        'removed': {'sessions': 1},
      });
      await tester.pumpAndSettle();
      expect(drawer, findsOneWidget);
      expect(find.text('新计划'), findsNothing);
      expect(chat.activeId, mainSession);
      expect(api.deletes, [
        {
          'scheduleRevision': '2'.padLeft(64, '0'),
          'scheduleDisposition': 'move-to-main',
        },
        {
          'scheduleRevision': '3'.padLeft(64, '0'),
          'scheduleDisposition': 'move-to-main',
        },
      ]);
    },
  );

  testWidgets('the idle chat starts directly below the Material app bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final address = Uri.parse('http://localhost');
    final chat = ChatController(MuseApi(address), () => MuseApi(address));
    addTearDown(chat.dispose);
    final appearance = AppearanceSettings(
      readPalette: () async => null,
      writePalette: (_) async {},
    );
    addTearDown(appearance.dispose);
    chat.synchronized = true;
    chat.active.revision = 'initial';
    chat.active.dirty = false;
    chat.active.history = List.generate(
      20,
      (index) => ChatMessage('$index', 'user', 'Message $index'),
    );
    chat.sessions = [...chat.sessions, const SessionEntry('topic', '随手记')];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
        home: WorkspacePage(
          chat: chat,
          appearance: appearance,
          connectionBuilder: (_) =>
              Scaffold(appBar: AppBar(title: const Text('服务器连接'))),
        ),
      ),
    );
    final bar = find.byType(AppBar);
    final list = find.byType(ListView);
    expect(
      find.descendant(of: bar, matching: find.text('主聊天')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.text('就绪'), findsNothing);
    expect(tester.getSize(bar).height, 64);
    expect(tester.getTopLeft(list).dy, tester.getBottomLeft(bar).dy);
    final barPosition = tester.getTopLeft(bar);
    await tester.drag(list, const Offset(0, 420));
    await tester.pumpAndSettle();
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      greaterThan(0),
    );
    expect(tester.getTopLeft(bar), barPosition);
    final title = find.descendant(of: bar, matching: find.text('主聊天'));
    final menu = find.byTooltip('打开导航菜单');
    expect(
      tester.getTopLeft(title).dx,
      greaterThan(tester.getTopRight(menu).dx),
    );
    expect(tester.getCenter(title).dx, lessThan(tester.getCenter(bar).dx));
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final drawer = find.byType(Drawer);
    expect(drawer, findsNothing);
    await tester.tap(find.byTooltip('打开导航菜单'));
    await tester.pumpAndSettle();
    expect(drawer, findsOneWidget);
    expect(
      find.descendant(of: drawer, matching: find.text('随手记')),
      findsOneWidget,
    );
    final create = find.descendant(of: drawer, matching: find.text('新建会话'));
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(drawer, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(drawer, findsNothing);

    final bottom = find.byType(NavigationBar);
    final destinations = tester.widget<NavigationBar>(bottom).destinations;
    expect(
      destinations.cast<NavigationDestination>().map((item) => item.label),
      ['聊天', '日程', '设置'],
    );
    expect((destinations[1] as NavigationDestination).enabled, isTrue);
    expect((destinations[2] as NavigationDestination).enabled, isTrue);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(bottom).selectedIndex, 2);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('配色'), findsNothing);
    await tester.tap(find.text('服务器连接'));
    await tester.pumpAndSettle();
    expect(bottom, findsNothing);
    expect(find.text('服务器连接'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(bottom).selectedIndex, 2);
    await tester.tap(find.text('聊天'));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(bottom).selectedIndex, 0);
    await tester.tap(find.byTooltip('打开导航菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: drawer, matching: find.text('设置')));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(bottom).selectedIndex, 2);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(bottom).selectedIndex, 0);
    expect(drawer, findsNothing);
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    await tester.pumpAndSettle();
    expect(tester.getSize(bar).height, 64);
    expect(tester.getBottomRight(find.byType(TextField)).dy, lessThan(400));
    expect(bottom, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
