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
    chat.sessions = [...chat.sessions, const SessionEntry('topic', '随手记')];
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
    final title = find.descendant(of: bar, matching: find.text('主聊天'));
    expect(tester.getCenter(title).dx, closeTo(180, 15));
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(find.text('切换会话'), findsOneWidget);
    expect(find.text('随手记'), findsOneWidget);
    expect(find.text('新建会话'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final bottom = find.byType(NavigationBar);
    final destinations = tester.widget<NavigationBar>(bottom).destinations;
    expect(
      destinations.cast<NavigationDestination>().map((item) => item.label),
      ['聊天', '待办', '新闻', '设置'],
    );
    expect((destinations[1] as NavigationDestination).enabled, isFalse);
    expect((destinations[2] as NavigationDestination).enabled, isFalse);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('服务器连接'));
    await tester.pumpAndSettle();
    expect(openedConnection, isTrue);
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    await tester.pumpAndSettle();
    expect(tester.getSize(bar).height, kToolbarHeight);
    expect(tester.getBottomRight(find.byType(TextField)).dy, lessThan(400));
    expect(bottom, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chat dates come from saved message metadata', (tester) async {
    final address = Uri.parse('http://localhost');
    final chat = ChatController(MuseApi(address), () => MuseApi(address));
    addTearDown(chat.dispose);
    chat.synchronized = true;
    final localTime = DateTime(2025, 3, 4, 10, 15);
    ChatMessage saved(String id, String role, String text, DateTime time) =>
        ChatMessage.fromJson({
          'id': id,
          'role': role,
          'content': text,
          'metadata': {'createdAt': time.toUtc().toIso8601String()},
        });
    chat.active.history = [
      saved('1', 'user', '问', localTime),
      saved('2', 'assistant', '答', localTime.add(const Duration(minutes: 1))),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: museTheme(Brightness.light),
        home: ChatPage(chat: chat, onConnection: () {}),
      ),
    );
    final localizations = MaterialLocalizations.of(
      tester.element(find.byType(AppBar)),
    );
    final day = localizations.formatShortDate(localTime);
    final date = find.text('$day 10:15');
    expect(date, findsOneWidget);
    expect(find.text('$day 10:16'), findsNothing);
    expect(
      tester.getTopLeft(date).dy - tester.getBottomLeft(find.byType(AppBar)).dy,
      lessThan(24),
    );
    expect(tester.takeException(), isNull);
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
