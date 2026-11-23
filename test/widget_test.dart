import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/api.dart';
import 'package:pi_muse_flutter/src/appearance.dart';
import 'package:pi_muse_flutter/src/chat.dart';
import 'package:pi_muse_flutter/src/chat_page.dart';
import 'package:pi_muse_flutter/src/visible_text.dart';

class _SessionApi extends MuseApi {
  _SessionApi() : super(Uri.parse('http://localhost'));

  String? topicTitle = '计划';
  int previews = 0;
  final deletes = <Json>[];
  final finalDelete = Completer<Json>();

  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    if (path == '/api/sessions') {
      return {
        'sessions': [
          {'id': mainSession, 'title': '默认会话'},
          if (topicTitle != null) {'id': 'topic', 'title': topicTitle},
        ],
      };
    }
    if (path == '/api/sessions/topic/schedules') {
      final revision = ++previews;
      return {
        'scheduleRevision': revision.toRadixString(16).padLeft(64, '0'),
        'jobs': [
          {'id': 'job', 'title': '任务 $revision'},
        ],
        'monitors': [
          {'id': 'monitor', 'title': '更新监控'},
        ],
      };
    }
    return {
      'sessionId': query?['sessionId'],
      'piSessionId': 'binding',
      'revision': 'empty',
      'messages': [],
    };
  }

  @override
  Future<Json> patch(String path, Json body) async {
    expect(path, '/api/sessions/topic');
    topicTitle = body['title'] as String;
    return {
      'session': {'id': 'topic', 'title': topicTitle},
    };
  }

  @override
  Future<Json> delete(String path, Json body) async {
    expect(path, '/api/sessions/topic');
    deletes.add(body);
    if (deletes.length == 1) {
      throw const ApiException(409, code: 'SESSION_SCHEDULES_CHANGED');
    }
    final receipt = await finalDelete.future;
    topicTitle = null;
    return receipt;
  }
}

class _MessageApi extends _SessionApi {
  final runFrames = StreamController<SseFrame>();
  final writes = <Json>[];
  final submissions = <Json>[];
  final stops = <Json>[];

  @override
  Stream<SseFrame> run(Json body) {
    submissions.add(body);
    return runFrames.stream;
  }

  @override
  Future<Json> post(String path, Json body) async {
    expect(path, '/api/conversation/stop');
    stops.add(body);
    return {'stopped': false};
  }

  @override
  Future<Json> put(String path, Json body) async {
    expect(path, '/api/sessions/main/messages/answer/feedback/reaction');
    writes.add(body);
    return {'reaction': body['reaction'], 'comments': []};
  }
}

void main() {
  testWidgets('message actions copy, react, quote and stop from the composer', (
    tester,
  ) async {
    final api = _MessageApi();
    final chat = ChatController(api, () => api)..synchronized = true;
    final appearance = AppearanceSettings(
      readPalette: () async => null,
      writePalette: (_) async {},
    );
    addTearDown(chat.dispose);
    addTearDown(appearance.dispose);
    final clipboard = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    chat.active
      ..binding = 'binding'
      ..revision = 'empty'
      ..dirty = false
      ..history = const [
        ChatMessage('question', 'user', 'Original question'),
        ChatMessage(
          'answer',
          'assistant',
          '<think>Hidden</think>**Visible reply**',
          feedbackAvailable: true,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(chat: chat, appearance: appearance, onConnection: () {}),
      ),
    );

    Finder action(String id, String label) => find.descendant(
      of: find.byKey(ValueKey(id)),
      matching: find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == label,
      ),
    );

    Future<void> tapAction(String id, String label) async {
      await tester.tap(action(id, label));
      await tester.pumpAndSettle();
    }

    expect(find.byTooltip('消息操作'), findsNothing);
    expect(action('question', '点赞'), findsNothing);
    await tapAction('question', '复制');
    await tapAction('answer', '复制');
    expect(clipboard, ['Original question', '**Visible reply**']);
    final snacks = tester.state<ScaffoldMessengerState>(
      find.byType(ScaffoldMessenger),
    );
    snacks.clearSnackBars();
    await tester.pumpAndSettle();
    await tapAction('answer', '点赞');
    expect(
      tester.widget<IconButton>(action('answer', '撤销点赞')).isSelected,
      true,
    );
    await tapAction('answer', '不喜欢');
    expect(
      tester.widget<IconButton>(action('answer', '撤销不喜欢')).isSelected,
      true,
    );
    await tapAction('answer', '撤销不喜欢');
    expect(
      tester.widget<IconButton>(action('answer', '不喜欢')).isSelected,
      false,
    );
    expect(api.writes, [
      {'piSessionId': 'binding', 'reaction': 'like'},
      {'piSessionId': 'binding', 'reaction': 'dislike'},
      {'piSessionId': 'binding', 'reaction': null},
    ]);

    final composer = find.byType(TextField);
    await tester.enterText(composer, 'Draft question');
    await tapAction('answer', '引用回复');
    expect(find.text('助手回复'), findsOneWidget);
    expect(find.text('**Visible reply**'), findsOneWidget);
    expect(
      tester.widget<TextField>(composer).controller!.text,
      'Draft question',
    );
    await tester.tap(find.byTooltip('移除引用'));
    await tester.pumpAndSettle();
    expect(find.text('助手回复'), findsNothing);
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    expect(find.byTooltip('停止回复'), findsOneWidget);
    await tester.enterText(composer, 'New question');
    await tester.pump();
    final interrupt = find.byTooltip('停止并发送');
    expect(interrupt, findsOneWidget);
    await tester.tap(interrupt);
    await tester.pumpAndSettle();
    expect(api.stops.single['runId'], api.submissions.single['runId']);
    expect(api.submissions, hasLength(1));
    expect(tester.widget<TextField>(composer).controller!.text, 'New question');
    await api.runFrames.close();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'manage topics from the drawer and re-confirm a changed task list',
    (tester) async {
      final api = _SessionApi();
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
          home: ChatPage(
            chat: chat,
            appearance: appearance,
            onConnection: () {},
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
    var openedConnection = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
        home: ChatPage(
          chat: chat,
          appearance: appearance,
          onConnection: () => openedConnection = true,
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
    final appearance = AppearanceSettings(
      readPalette: () async => null,
      writePalette: (_) async {},
    );
    addTearDown(appearance.dispose);
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
        theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
        home: ChatPage(chat: chat, appearance: appearance, onConnection: () {}),
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
    final appearance = AppearanceSettings(
      readPalette: () async => null,
      writePalette: (_) async {},
    );
    addTearDown(appearance.dispose);
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
        theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: ChatPage(chat: chat, appearance: appearance, onConnection: () {}),
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
