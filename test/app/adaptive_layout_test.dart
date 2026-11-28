import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/app/adaptive_layout.dart';
import 'package:pi_muse_flutter/src/network/api.dart';
import 'package:pi_muse_flutter/src/features/appearance/appearance.dart';
import 'package:pi_muse_flutter/src/features/chat/chat_controller.dart';
import 'package:pi_muse_flutter/src/features/chat/chat_page.dart';
import 'package:pi_muse_flutter/src/app/workspace_page.dart';
import 'package:pi_muse_flutter/src/features/connection/connection_page.dart';

void main() {
  test('workspace uses Android window size classes at each breakpoint', () {
    for (final (width, height, rail, twoPanes) in [
      (390.0, 844.0, false, false),
      (599.0, 961.0, false, false),
      (600.0, 961.0, true, false),
      (839.0, 600.0, true, false),
      (840.0, 479.0, true, false),
      (840.0, 480.0, true, true),
      (840.0, 1100.0, true, true),
    ]) {
      final layout = WorkspaceLayout.fromSize(Size(width, height));
      expect(layout.useRail, rail, reason: '${width}dp × ${height}dp');
      expect(layout.useSplitPane, twoPanes, reason: '${width}dp × ${height}dp');
    }
  });

  Widget buildApp(
    ChatController chat,
    AppearanceSettings appearance, {
    WidgetBuilder? connectionBuilder,
  }) => MaterialApp(
    theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
    home: WorkspacePage(
      key: ObjectKey(chat),
      chat: chat,
      appearance: appearance,
      connectionBuilder: connectionBuilder ?? (_) => const SizedBox(),
    ),
  );

  (ChatController, AppearanceSettings) createDeps() {
    final api = MuseApi(Uri.parse('http://localhost'));
    final chat = ChatController(api, () => api);
    chat.synchronized = true;
    chat.active.revision = 'saved';
    chat.active.history = const [ChatMessage('m1', 'user', '测试消息')];
    chat.sessions = [...chat.sessions, const SessionEntry('topic-1', '研究笔记')];
    final appearance = AppearanceSettings(
      readPalette: () async => null,
      writePalette: (_) async {},
    );
    return (chat, appearance);
  }

  testWidgets(
    'the compact bottom bar uses the Expressive height and real destinations',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (chat, appearance) = createDeps();
      addTearDown(chat.dispose);
      addTearDown(appearance.dispose);
      await tester.pumpWidget(buildApp(chat, appearance));
      final bar = find.byType(NavigationBar);
      expect(tester.getSize(bar).height, 64);
      for (final label in ['聊天', '日程', '设置']) {
        final destination = find.widgetWithText(NavigationDestination, label);
        expect(
          tester.widget<NavigationDestination>(destination).enabled,
          isTrue,
        );
        expect(tester.getSize(destination).height, greaterThanOrEqualTo(48));
      }
      expect(find.text('新闻'), findsNothing);
    },
  );

  testWidgets(
    'medium portrait keeps the leading rail and one pane when the keyboard opens',
    (tester) async {
      tester.view.physicalSize = const Size(601, 961);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      final (chat, appearance) = createDeps();
      addTearDown(chat.dispose);
      addTearDown(appearance.dispose);

      await tester.pumpWidget(buildApp(chat, appearance));
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byTooltip('打开导航菜单'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 420);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byTooltip('打开导航菜单'), findsOneWidget);
    },
  );

  testWidgets(
    'expanded window places the rail at the leading edge and preserves the draft when resizing',
    (tester) async {
      tester.view.physicalSize = const Size(961, 580);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      final (chat, appearance) = createDeps();
      addTearDown(chat.dispose);
      addTearDown(appearance.dispose);

      await tester.pumpWidget(buildApp(chat, appearance));
      expect(find.byType(NavigationBar), findsNothing);
      final rail = find.byType(NavigationRail);
      expect(rail, findsOneWidget);

      // 导航轨、会话栏、聊天正文按起始侧顺序排列。
      final appBar = find.byType(AppBar);
      expect(
        tester.getTopRight(rail).dx,
        lessThan(tester.getTopLeft(find.text('研究笔记')).dx),
      );
      expect(tester.getSize(rail).width, 96);
      expect(tester.getSize(appBar).height, 64);

      // 宽横屏默认常驻左侧会话栏，且可一键折叠与展开。
      expect(find.text('研究笔记'), findsOneWidget);
      expect(find.text('新建会话'), findsOneWidget);
      final chatWidthBeforeCollapse = tester.getSize(appBar).width;
      await tester.tap(find.byTooltip('收起会话列表'));
      await tester.pumpAndSettle();
      expect(find.text('研究笔记'), findsNothing);
      expect(
        tester.getSize(appBar).width,
        greaterThan(chatWidthBeforeCollapse),
      );
      await tester.tap(find.byTooltip('展开会话列表'));
      await tester.pumpAndSettle();
      expect(find.text('研究笔记'), findsOneWidget);

      // 键盘弹起时导航与输入区不溢出。
      await tester.enterText(find.byType(TextField), '旋转前写一半的草稿');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      // 窗口缩窄时切换为底栏，聊天草稿原样保留。
      final chatState = tester.state(find.byType(ChatPage));
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.state(find.byType(ChatPage)), same(chatState));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '旋转前写一半的草稿',
      );
    },
  );

  testWidgets('portrait settings explain unavailable server entries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (chat, appearance) = createDeps();
    chat.expired = true;
    addTearDown(chat.dispose);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(buildApp(chat, appearance));
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('应用与连接'), findsOneWidget);
    expect(find.text('扩展与同步'), findsOneWidget);
    final unavailable = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'MCP 服务'),
    );
    expect(unavailable.enabled, isFalse);
    expect(unavailable.onTap, isNull);
    expect(find.text('服务器连接已失效'), findsNWidgets(2));
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets(
    'landscape tablet opens Settings in split-pane master-detail with leading rail',
    (tester) async {
      tester.view.physicalSize = const Size(961, 580);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final (chat, appearance) = createDeps();
      addTearDown(chat.dispose);
      addTearDown(appearance.dispose);

      await tester.pumpWidget(buildApp(chat, appearance));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      // 起始侧导航常驻，设置目录与详情并排，直接展示默认详情页「外观」。
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('外观'), findsNWidgets(2));
      expect(find.byType(AppBar), findsNWidgets(2));
      expect(tester.getRect(find.widgetWithText(AppBar, '设置')).bottom, 64);
      expect(tester.getRect(find.widgetWithText(AppBar, '外观')).bottom, 64);
      expect(find.text('主题模式'), findsOneWidget);
      expect(find.text('配色'), findsOneWidget);

      // 点选左侧设置目录直接原位切换右侧详情页，不压入新路由。
      await tester.tap(find.text('MCP 服务'));
      await tester.pump();
      expect(find.text('主题模式'), findsNothing);
      expect(find.text('MCP 服务'), findsNWidgets(2));

      await tester.tap(find.text('外观'));
      await tester.pump();
      expect(find.text('主题模式'), findsOneWidget);

      // 切回聊天时导航仍可无缝切回。
      await tester.tap(find.text('聊天'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    },
  );

  testWidgets(
    'landscape tablet opens ConnectionPage in split-pane settings and defers confirmation until submit',
    (tester) async {
      tester.view.physicalSize = const Size(961, 580);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final (chat, appearance) = createDeps();
      addTearDown(chat.dispose);
      addTearDown(appearance.dispose);

      var allowConnect = false;
      var beforeCalls = 0;
      Uri? submittedUri;
      String? submittedKey;

      await tester.pumpWidget(
        buildApp(
          chat,
          appearance,
          connectionBuilder: (_) => ConnectionPage(
            settingsMode: true,
            address: Uri.parse('http://localhost:12330'),
            onBeforeConnect: (_) async {
              beforeCalls += 1;
              return allowConnect;
            },
            onConnect: (uri, key) async {
              submittedUri = uri;
              submittedKey = key;
            },
          ),
        ),
      );

      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('服务器连接'));
      await tester.pumpAndSettle();

      // 保持设置双栏与起始侧导航轨，不提前弹窗阻断，样式统一为顶部卡片。
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('服务器连接'), findsNWidgets(2));
      expect(find.text('当前连接'), findsOneWidget);
      expect(find.text('保存并连接'), findsOneWidget);
      expect(find.text('Pi Muse'), findsNothing);
      expect(beforeCalls, 0);

      await tester.enterText(
        find.widgetWithText(TextField, '服务器地址'),
        'http://127.0.0.1:12331',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '访问密钥'),
        'secret-key',
      );
      await tester.ensureVisible(find.text('保存并连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并连接'));
      await tester.pumpAndSettle();
      expect(beforeCalls, 1);
      expect(submittedUri, isNull);

      allowConnect = true;
      await tester.tap(find.text('保存并连接'));
      await tester.pumpAndSettle();
      expect(beforeCalls, 2);
      expect(submittedUri, Uri.parse('http://127.0.0.1:12331'));
      expect(submittedKey, 'secret-key');
    },
  );

  testWidgets(
    'initial unconnected ConnectionPage keeps centered welcome layout',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
          home: ConnectionPage(onConnect: (_, _) async {}),
        ),
      );
      expect(find.text('Pi Muse'), findsOneWidget);
      expect(find.text('连接你的助手服务器'), findsOneWidget);
      expect(find.text('连接'), findsOneWidget);
    },
  );
}
