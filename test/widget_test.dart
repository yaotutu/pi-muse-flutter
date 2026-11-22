import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/main.dart';
import 'package:pi_muse_flutter/src/api.dart';
import 'package:pi_muse_flutter/src/chat.dart';
import 'package:pi_muse_flutter/src/chat_page.dart';
import 'package:pi_muse_flutter/src/visible_text.dart';

void main() {
  test('assistant projection hides incomplete and nested thinking blocks', () {
    expect(visibleAssistantText('Hello <thi'), 'Hello ');
    expect(visibleAssistantText('<think>private'), '');
    expect(
      visibleAssistantText('<THINK>hidden <think>nested</think></THINK>\n你好'),
      '你好',
    );
    expect(visibleAssistantText('`<think>` and 1 < 2'), '`<think>` and 1 < 2');
    const code = '```text\n<think>literal\n```\n<think>hidden';
    expect(visibleAssistantText(code), '```text\n<think>literal\n```\n');
  });

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
    chat.synchronized = true;
    chat.active.revision = 'initial';
    chat.active.dirty = false;
    chat.active.history = List.generate(
      20,
      (index) => ChatMessage('$index', 'user', 'Message $index'),
    );
    var openedConnection = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: museTheme(Brightness.light),
        home: ChatPage(chat: chat, onConnection: () => openedConnection = true),
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
    expect(tester.getSize(bar).height, kToolbarHeight);
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
    await tester.tap(find.byTooltip('服务器连接'));
    expect(openedConnection, isTrue);
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    await tester.pumpAndSettle();
    expect(tester.getSize(bar).height, kToolbarHeight);
    expect(tester.getBottomRight(find.byType(TextField)).dy, lessThan(400));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('approval banner opens the full preview at large text sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final address = Uri.parse('http://localhost');
    final chat = ChatController(MuseApi(address), () => MuseApi(address));
    addTearDown(chat.dispose);
    chat.synchronized = true;
    chat.approvals['approval'] = Approval.fromJson({
      'id': 'approval',
      'sessionId': mainSession,
      'revision': 1,
      'status': 'pending',
      'preview': {
        'scope': 'workspace',
        'path': 'files/check.txt',
        'before': '',
        'after': 'test',
        'beforeExists': false,
      },
      'expiresAt': '2099-01-01T00:00:00Z',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: museTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: ChatPage(chat: chat, onConnection: () {}),
      ),
    );
    final banner = find.byType(MaterialBanner);
    final action = find.widgetWithText(TextButton, '查看修改');
    expect(find.descendant(of: banner, matching: action), findsOneWidget);
    expect(find.text('有文件修改待确认'), findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('确认文件修改'), findsOneWidget);
    expect(find.text('files/check.txt'), findsOneWidget);
    expect(find.text('修改前'), findsOneWidget);
    expect(find.text('修改后'), findsOneWidget);
    expect(find.text('test'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
