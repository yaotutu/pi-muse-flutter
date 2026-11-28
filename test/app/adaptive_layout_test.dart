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
  test(
    'WorkspaceLayout classifies phone, portrait tablet, split view, and landscape tablet',
    () {
      final phonePortrait = WorkspaceLayout.fromSize(const Size(390, 844));
      expect(phonePortrait.useRightRail, isFalse);
      expect(phonePortrait.canPinSidebar, isFalse);
      expect(phonePortrait.useSplitPane, isFalse);
      expect(phonePortrait.compactToolbar, isFalse);

      // 竖屏平板（如 800x1280 @213dpi 约 601x961 dp）保持底栏与抽屉，不挤占横向空间。
      final tabletPortrait = WorkspaceLayout.fromSize(const Size(601, 961));
      expect(tabletPortrait.useRightRail, isFalse);
      expect(tabletPortrait.canPinSidebar, isFalse);
      expect(tabletPortrait.useSplitPane, isFalse);

      // 窄分屏窗口退回底栏。
      final splitNarrow = WorkspaceLayout.fromSize(const Size(480, 580));
      expect(splitNarrow.useRightRail, isFalse);
      expect(splitNarrow.canPinSidebar, isFalse);

      // 800x600 中等横窗切至右侧竖排导航，不常驻双栏。
      final mediumLandscape = WorkspaceLayout.fromSize(const Size(800, 600));
      expect(mediumLandscape.useRightRail, isTrue);
      expect(mediumLandscape.canPinSidebar, isFalse);
      expect(mediumLandscape.useSplitPane, isFalse);
      expect(mediumLandscape.compactToolbar, isTrue);

      // 横屏平板（961x580 dp）启用右侧竖排导航、可常驻左侧会话栏、设置双栏与紧凑顶栏。
      final tabletLandscape = WorkspaceLayout.fromSize(const Size(961, 580));
      expect(tabletLandscape.useRightRail, isTrue);
      expect(tabletLandscape.canPinSidebar, isTrue);
      expect(tabletLandscape.useSplitPane, isTrue);
      expect(tabletLandscape.compactToolbar, isTrue);
      expect(tabletLandscape.toolbarHeight, 48);
    },
  );

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
    'portrait tablet keeps bottom NavigationBar even with soft keyboard open',
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
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      // 弹起键盘导致可视高度小于宽度，仍不能误判为横屏。
      tester.view.viewInsets = const FakeViewPadding(bottom: 420);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsNothing);
    },
  );

  testWidgets(
    'landscape tablet places NavigationRail on the right, supports collapsible left sidebar, and keeps draft across rotation',
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

      // 导航栏必须在最右侧，聊天内容在其左侧。
      final appBar = find.byType(AppBar);
      expect(
        tester.getTopLeft(rail).dx,
        greaterThanOrEqualTo(tester.getTopRight(appBar).dx),
      );
      expect(tester.getSize(appBar).height, 48);

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

      // 键盘弹起时右侧导航与输入区不溢出。
      await tester.enterText(find.byType(TextField), '旋转前写一半的草稿');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      // 旋转到竖屏：切换为底栏，聊天草稿原样保留。
      final chatState = tester.state(find.byType(ChatPage));
      tester.view.physicalSize = const Size(601, 961);
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

  testWidgets(
    'landscape tablet opens Settings in split-pane master-detail with right rail',
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

      // 右侧导航常驻，左侧为设置目录，中间直接展示默认详情页「外观」。
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('外观'), findsNWidgets(2));
      expect(find.text('主题模式'), findsOneWidget);
      expect(find.text('配色'), findsOneWidget);

      // 点选左侧设置目录直接原位切换中间详情页，不压入新路由。
      await tester.tap(find.text('MCP 服务'));
      await tester.pump();
      expect(find.text('主题模式'), findsNothing);
      expect(find.text('MCP 服务'), findsNWidgets(2));

      await tester.tap(find.text('外观'));
      await tester.pump();
      expect(find.text('主题模式'), findsOneWidget);

      // 切回聊天时右侧导航仍可无缝切回。
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

      // 保持设置双栏与右侧导航栏，不提前弹窗阻断，样式统一为顶部卡片。
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
