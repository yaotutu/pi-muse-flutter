import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/api.dart';
import 'package:pi_muse_flutter/src/appearance.dart';
import 'package:pi_muse_flutter/src/chat.dart';
import 'package:pi_muse_flutter/src/chat_page.dart';
import 'package:pi_muse_flutter/src/visible_text.dart';

ChatController _chatWithHistory(List<ChatMessage> history) {
  final address = Uri.parse('http://localhost');
  final chat = ChatController(MuseApi(address), () => MuseApi(address));
  chat.synchronized = true;
  chat.active.revision = 'initial';
  chat.active.dirty = false;
  chat.active.history = history;
  return chat;
}

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
  Object? reaction;
  bool saved = false;

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
    const feedbackPath = '/api/sessions/main/messages/answer/feedback';
    if (body.containsKey('saved')) {
      expect(path, '$feedbackPath/saved');
      saved = body['saved'] as bool;
    } else {
      expect(path, '$feedbackPath/reaction');
      reaction = body['reaction'];
    }
    writes.add(body);
    return {'reaction': reaction, 'saved': saved, 'comments': []};
  }
}

class _ExecutionApi extends _SessionApi {
  final runCursors = <String?>[];
  final frames = StreamController<SseFrame>();
  int subscriptions = 0;

  @override
  Stream<SseFrame> events() {
    subscriptions++;
    return frames.stream;
  }

  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    switch (path) {
      case '/api/runs':
        expect(query?['sessionId'], mainSession);
        final cursor = query?['cursor'];
        runCursors.add(cursor);
        return {
          'runs': [
            if (cursor == null)
              {
                'sessionId': mainSession,
                'runId': 'first-run',
                'revision': 2,
                'source': 'chat',
                'status': 'succeeded',
                'title': '第一轮调研',
                'label': '已完成',
                'startedAt': '2026-01-02T00:00:00.000Z',
                'endedAt': '2026-01-02T00:00:05.000Z',
                'steps': [
                  {
                    'id': 'step-search',
                    'parentId': null,
                    'kind': 'tool',
                    'title': '搜索网页',
                    'detail': 'pi muse',
                    'status': 'succeeded',
                    'result': '已完成',
                    'toolName': 'search_web',
                    'approvalId': null,
                    'startedAt': '2026-01-02T00:00:00.000Z',
                    'endedAt': '2026-01-02T00:00:02.000Z',
                  },
                ],
              }
            else
              {
                'sessionId': mainSession,
                'runId': 'second-run',
                'revision': 2,
                'source': 'chat',
                'status': 'succeeded',
                'title': '第二轮读取',
                'label': '已完成',
                'startedAt': '2026-01-01T00:00:00.000Z',
                'endedAt': '2026-01-01T00:00:03.000Z',
                'steps': [
                  {
                    'id': 'step',
                    'parentId': null,
                    'kind': 'tool',
                    'title': '读取测试文件',
                    'detail': 'test.txt',
                    'status': 'succeeded',
                    'result': '已完成',
                    'toolName': 'read',
                    'approvalId': null,
                    'startedAt': '2026-01-01T00:00:00.000Z',
                    'endedAt': '2026-01-01T00:00:02.000Z',
                  },
                ],
              },
          ],
          'hasMore': cursor == null,
          'nextCursor': cursor == null ? 'opaque-cursor' : null,
        };
      case '/api/approvals':
        expect(query?['sessionId'], mainSession);
        return {
          'approvals': [
            {
              'sessionId': mainSession,
              'id': 'past',
              'status': 'approved',
              'title': '历史文件修改',
            },
          ],
          'nextCursor': null,
        };
      case '/api/approvals/past':
        return {
          'id': 'past',
          'sessionId': mainSession,
          'revision': 3,
          'status': 'approved',
          'expiresAt': '2099-01-01T00:00:00Z',
          'preview': {
            'scope': 'workspace',
            'path': 'test.txt',
            'before': '原文',
            'after': '新文',
            'beforeExists': true,
          },
          'execution': {'status': 'failed', 'result': '目标文件版本已变化'},
        };
      default:
        return super.get(path, query: query);
    }
  }
}

void main() {
  testWidgets(
    'execution details open directly and scope execution records and approvals to chat',
    (tester) async {
      final api = _ExecutionApi();
      final chat = ChatController(api, () => api);
      final appearance = AppearanceSettings(
        readPalette: () async => null,
        writePalette: (_) async {},
      );
      addTearDown(chat.dispose);
      addTearDown(appearance.dispose);
      chat.start();
      api.frames.add(
        const SseFrame(
          event: 'ready',
          data: {
            'instanceId': 'test-instance',
            'sessionStatuses': [
              {
                'sessionId': mainSession,
                'runId': 'active',
                'revision': 1,
                'status': 'running',
                'label': '正在执行工具',
                'tools': [
                  {'label': '读取资料', 'status': 'running'},
                ],
              },
              {
                'sessionId': 'topic',
                'runId': 'other',
                'revision': 1,
                'status': 'running',
                'label': '其他会话运行',
              },
            ],
            'pendingApprovals': [],
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            chat: chat,
            appearance: appearance,
            onConnection: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保留草稿');
      await tester.tap(find.byTooltip('执行详情'));
      await tester.pumpAndSettle();
      expect(find.text('执行记录'), findsOneWidget);
      expect(find.text('审批'), findsOneWidget);
      expect(find.text('动态'), findsNothing);
      expect(find.text('历史'), findsNothing);
      expect(find.text('读取资料'), findsOneWidget);
      expect(find.text('第一轮调研'), findsOneWidget);
      expect(find.text('其他会话运行'), findsNothing);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(api.runCursors.take(2).toList(), [null, 'opaque-cursor']);
      await tester.tap(find.text('第二轮读取'));
      await tester.pumpAndSettle();
      expect(find.text('读取测试文件 · test.txt'), findsOneWidget);
      await tester.tap(find.text('审批'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看审批历史'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('历史文件修改'));
      await tester.pumpAndSettle();
      expect(find.text('原文'), findsOneWidget);
      expect(find.text('新文'), findsOneWidget);
      expect(find.text('已批准'), findsOneWidget);
      expect(find.text('文件写入失败'), findsOneWidget);
      expect(find.text('批准修改'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('保留草稿'), findsOneWidget);
      expect(api.subscriptions, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'inline process bar is hidden for 0-step replies and toggles steps inline for tool-using replies',
    (tester) async {
      final api = _ExecutionApi();
      final chat = ChatController(api, () => api);
      final appearance = AppearanceSettings(
        readPalette: () async => null,
        writePalette: (_) async {},
      );
      addTearDown(chat.dispose);
      addTearDown(appearance.dispose);
      chat.start();
      api.frames.add(
        const SseFrame(
          event: 'ready',
          data: {
            'instanceId': 'test-instance',
            'sessionStatuses': [],
            'pendingApprovals': [],
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            chat: chat,
            appearance: appearance,
            onConnection: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      chat.active.history = const [
        ChatMessage('u1', 'user', '1+1等于几'),
        ChatMessage('a1', 'assistant', '等于 2。', runId: 'plain-run'),
        ChatMessage('u2', 'user', '搜索并改写文档'),
        ChatMessage('a2', 'assistant', '已完成并请求确认。', runId: 'tool-run'),
      ];
      api.frames.add(
        const SseFrame(
          event: 'session_status_updated',
          data: {
            'instanceId': 'test-instance',
            'sessionId': mainSession,
            'runId': 'plain-run',
            'revision': 2,
            'status': 'succeeded',
            'steps': [],
          },
        ),
      );
      api.frames.add(
        const SseFrame(
          event: 'session_status_updated',
          data: {
            'instanceId': 'test-instance',
            'sessionId': mainSession,
            'runId': 'tool-run',
            'revision': 3,
            'status': 'succeeded',
            'steps': [
              {
                'id': 's1',
                'parentId': null,
                'kind': 'tool',
                'title': '搜索网页',
                'detail': 'pi muse docs',
                'status': 'succeeded',
                'result': '已完成',
                'toolName': 'search_web',
                'approvalId': null,
                'startedAt': '2026-01-01T00:00:00.000Z',
                'endedAt': '2026-01-01T00:00:01.000Z',
              },
              {
                'id': 's2',
                'parentId': null,
                'kind': 'approval',
                'title': '请求修改文件',
                'detail': 'notes/plan.md',
                'status': 'succeeded',
                'result': '已批准',
                'toolName': null,
                'approvalId': 'past',
                'startedAt': '2026-01-01T00:00:01.000Z',
                'endedAt': '2026-01-01T00:00:02.000Z',
              },
            ],
          },
        ),
      );
      await tester.pumpAndSettle();

      // Plain reply has no bar; tool reply shows collapsed 1-line bar.
      expect(find.text('已执行 2 步'), findsOneWidget);
      expect(find.text('搜索网页 · pi muse docs'), findsNothing);

      await tester.tap(find.text('已执行 2 步'));
      await tester.pumpAndSettle();
      expect(find.text('搜索网页 · pi muse docs'), findsOneWidget);
      expect(find.text('请求修改文件 · notes/plan.md'), findsOneWidget);

      await tester.tap(find.text('请求修改文件 · notes/plan.md'));
      await tester.pumpAndSettle();
      expect(find.text('原文'), findsOneWidget);
      expect(find.text('新文'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('已执行 2 步'));
      await tester.pumpAndSettle();
      expect(find.text('搜索网页 · pi muse docs'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

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
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('question')),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );
    await tapAction('answer', '复制');
    expect(clipboard, ['**Visible reply**']);
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
    await tapAction('answer', '收藏');
    expect(
      tester.widget<IconButton>(action('answer', '取消收藏')).isSelected,
      true,
    );
    expect(
      tester.widget<IconButton>(action('answer', '撤销点赞')).isSelected,
      true,
    );
    await tapAction('answer', '不喜欢');
    expect(
      tester.widget<IconButton>(action('answer', '撤销不喜欢')).isSelected,
      true,
    );
    expect(
      tester.widget<IconButton>(action('answer', '取消收藏')).isSelected,
      true,
    );
    await tapAction('answer', '取消收藏');
    expect(tester.widget<IconButton>(action('answer', '收藏')).isSelected, false);
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
      {'piSessionId': 'binding', 'saved': true},
      {'piSessionId': 'binding', 'reaction': 'dislike'},
      {'piSessionId': 'binding', 'saved': false},
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

  testWidgets('a chat that fits does not overscroll from a message', (
    tester,
  ) async {
    final chat = _chatWithHistory([
      const ChatMessage('reply', 'assistant', 'A short reply'),
    ]);
    addTearDown(chat.dispose);
    final appearance = AppearanceSettings(
      readPalette: () async => null,
      writePalette: (_) async {},
    );
    addTearDown(appearance.dispose);
    final overscroll = <OverscrollNotification>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
        home: NotificationListener<OverscrollNotification>(
          onNotification: (notification) {
            overscroll.add(notification);
            return false;
          },
          child: ChatPage(
            chat: chat,
            appearance: appearance,
            onConnection: () async {},
          ),
        ),
      ),
    );
    final list = find.byType(ListView);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(position.maxScrollExtent, 0);
    expect(
      tester.getTopLeft(list).dy,
      tester.getBottomLeft(find.byType(AppBar)).dy,
    );
    await tester.drag(find.text('A short reply'), const Offset(0, -90));
    await tester.pumpAndSettle();
    expect(overscroll, isEmpty);
    expect(position.pixels, 0);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('vertical chat drags work from text, code and message gaps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final chat = _chatWithHistory(
      List.generate(
        8,
        (index) => [
          ChatMessage('user-$index', 'user', 'User message $index'),
          ChatMessage(
            'reply-$index',
            'assistant',
            'Assistant reply $index\n\n```text\n${'wide code ' * 16}$index\n```',
          ),
        ],
      ).expand((pair) => pair).toList(),
    );
    addTearDown(chat.dispose);
    final appearance = AppearanceSettings(
      readPalette: () async => null,
      writePalette: (_) async {},
    );
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
        home: ChatPage(
          chat: chat,
          appearance: appearance,
          onConnection: () async {},
        ),
      ),
    );
    final list = find.byType(ListView);
    final scrollables = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollables.first).position;
    expect(position.pixels, 0);
    const initialOffset = 90.0;
    position.jumpTo(initialOffset);
    await tester.pumpAndSettle();
    final user = find.text('User message 7').hitTestable();
    final reply = find.text('Assistant reply 7').hitTestable();
    final code = find.text('${'wide code ' * 16}7');
    final codeViewport = find.ancestor(
      of: code,
      matching: find.byType(SingleChildScrollView),
    );
    final gap = Offset(
      tester.getCenter(list).dx,
      (tester.getBottomLeft(find.byKey(const ValueKey('user-7'))).dy +
              tester.getTopLeft(find.byKey(const ValueKey('reply-7'))).dy) /
          2,
    );
    final starts = {
      'message gap': gap,
      'user text': tester.getCenter(user),
      'assistant text': tester.getCenter(reply),
      'code text': tester
          .getRect(code)
          .intersect(tester.getRect(codeViewport))
          .center,
    };
    final distances = <String, double>{};
    for (final start in starts.entries) {
      final gesture = await tester.startGesture(start.value);
      // Holding before moving used to activate selection instead of scrolling.
      await tester.pump(const Duration(milliseconds: 720));
      for (var step = 0; step < 5; step++) {
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      distances[start.key] = initialOffset - position.pixels;
      await gesture.up();
      await tester.pumpAndSettle();
      position.jumpTo(initialOffset);
      await tester.pumpAndSettle();
    }
    expect(
      distances.values,
      everyElement(closeTo(50, 1)),
      reason: '$distances',
    );
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    expect(find.byType(SelectionArea), findsNothing);
    final horizontal = tester
        .state<ScrollableState>(
          find
              .descendant(of: codeViewport, matching: find.byType(Scrollable))
              .first,
        )
        .position;
    final codeGesture = await tester.startGesture(starts['code text']!);
    for (var step = 0; step < 11; step++) {
      await codeGesture.moveBy(const Offset(-10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final codeTravel = horizontal.pixels;
    await codeGesture.up();
    await tester.pumpAndSettle();
    expect(codeTravel, greaterThan(80));
    expect(position.pixels, closeTo(initialOffset, 1));

    final select = find.byTooltip('选择文字').hitTestable().first;
    final fromButton = await tester.startGesture(tester.getCenter(select));
    for (var step = 0; step < 5; step++) {
      await fromButton.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, closeTo(initialOffset - 50, 1));
    await fromButton.up();
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsNothing);
    position.jumpTo(initialOffset);
    await tester.pumpAndSettle();

    await tester.tap(select);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsNothing);
    expect(position.pixels, closeTo(initialOffset, 1));
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('both screen halves move the transcript in both directions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final chat = _chatWithHistory([
      for (var i = 0; i < 16; i++) ...[
        ChatMessage('user-$i', 'user', 'Question $i'),
        ChatMessage(
          'reply-$i',
          'assistant',
          'Answer $i\n\nA paragraph with a few words.\n\nAnother paragraph.',
        ),
      ],
    ]);
    addTearDown(chat.dispose);
    final appearance = AppearanceSettings(
      readPalette: () async => null,
      writePalette: (_) async {},
    );
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(chat: chat, appearance: appearance, onConnection: () {}),
      ),
    );
    final list = find.byType(ListView);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(position.pixels, 0);
    expect(
      position.maxScrollExtent,
      greaterThan(2 * position.viewportDimension),
    );

    Offset textInHalf({required bool upper}) {
      final view = tester.getRect(list).deflate(24);
      final half = upper
          ? Rect.fromLTRB(view.left, view.top, view.right, view.center.dy)
          : Rect.fromLTRB(view.left, view.center.dy, view.right, view.bottom);
      final textWidgets = find
          .descendant(
            of: list,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  RegExp(
                    r'^(?:(?:Question|Answer) \d+|A paragraph with a few words\.|Another paragraph\.)$',
                  ).hasMatch(
                    widget.data ?? widget.textSpan?.toPlainText() ?? '',
                  ),
            ),
          )
          .hitTestable();
      for (final element in textWidgets.evaluate()) {
        final text = find.byElementPredicate(
          (candidate) => identical(candidate, element),
        );
        final rect = tester.getRect(text);
        if (half.contains(rect.center)) return rect.center;
      }
      throw StateError(
        'No message text found in ${upper ? 'upper' : 'lower'} half',
      );
    }

    Future<void> checkDrag(
      double origin,
      double dy, {
      required bool upper,
    }) async {
      position.jumpTo(origin);
      await tester.pumpAndSettle();
      final start = textInHalf(upper: upper);
      final gesture = await tester.startGesture(start);
      for (var step = 0; step < 12; step++) {
        await gesture.moveBy(Offset(0, dy / 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final moved = position.pixels - origin;
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        moved,
        closeTo(dy, 1),
        reason: '${upper ? 'upper' : 'lower'} message from $origin',
      );
    }

    for (final upper in [true, false]) {
      await checkDrag(0, 280, upper: upper);
      expect(find.text('Answer 14').hitTestable(), findsOneWidget);
      await checkDrag(440, -120, upper: upper);
      await checkDrag(440, 120, upper: upper);
    }

    // The composer keyboard changes the available height, not the scroll owner.
    addTearDown(tester.view.resetViewInsets);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    await checkDrag(440, 120, upper: false);
    final readingOffset = position.pixels;
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(readingOffset, 1));
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets(
    'a barely overflowing transcript stops at either edge without stretching',
    (tester) async {
      tester.view.physicalSize = const Size(360, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final chat = _chatWithHistory([
        const ChatMessage('older', 'assistant', 'Older\nLine two\nLine three'),
        const ChatMessage('newer', 'assistant', 'Newer\nLine two\nLine three'),
      ]);
      addTearDown(chat.dispose);
      final appearance = AppearanceSettings(
        readPalette: () async => null,
        writePalette: (_) async {},
      );
      addTearDown(appearance.dispose);
      final boundaries = <OverscrollNotification>[];
      final indicators = <OverscrollIndicatorNotification>[];
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationListener<OverscrollNotification>(
            onNotification: (notification) {
              if (notification.depth == 0) boundaries.add(notification);
              return false;
            },
            child: NotificationListener<OverscrollIndicatorNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) indicators.add(notification);
                return false;
              },
              child: ChatPage(
                chat: chat,
                appearance: appearance,
                onConnection: () {},
              ),
            ),
          ),
        ),
      );
      final list = find.byType(ListView);
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      final end = position.maxScrollExtent;
      expect(end, inExclusiveRange(0, 130));
      for (final (offset, dy, message) in [
        (0.0, -170.0, 'Newer\nLine two\nLine three'),
        (end, 170.0, 'Older\nLine two\nLine three'),
      ]) {
        position.jumpTo(offset);
        await tester.pumpAndSettle();
        boundaries.clear();
        indicators.clear();
        await tester.drag(find.text(message), Offset(0, dy));
        await tester.pumpAndSettle();
        expect(position.pixels, closeTo(offset, 0.1));
        expect(boundaries, isNotEmpty);
        expect(
          indicators.where((notification) => notification.accepted),
          isEmpty,
        );
      }
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
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
        home: ChatPage(
          chat: chat,
          appearance: appearance,
          onConnection: () => navigator.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) =>
                  Scaffold(appBar: AppBar(title: const Text('服务器连接'))),
            ),
          ),
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
    expect(tester.widget<NavigationBar>(bottom).selectedIndex, 3);
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
    expect(tester.widget<NavigationBar>(bottom).selectedIndex, 3);
    await tester.tap(find.text('聊天'));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(bottom).selectedIndex, 0);
    await tester.tap(find.byTooltip('打开导航菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: drawer, matching: find.text('设置')));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(bottom).selectedIndex, 3);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(bottom).selectedIndex, 0);
    expect(drawer, findsNothing);
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

  testWidgets(
    'shows processing card and stop button for restored run, and terminal notice on failure',
    (tester) async {
      final api = _RestoredRunApi();
      final chat = ChatController(api, () => api);
      final appearance = AppearanceSettings(
        readPalette: () async => null,
        writePalette: (_) async {},
      );
      addTearDown(chat.dispose);
      addTearDown(appearance.dispose);
      chat.start();
      api.frames.add(
        const SseFrame(
          event: 'ready',
          data: {
            'instanceId': 'test-instance',
            'sessionStatuses': [
              {
                'sessionId': mainSession,
                'runId': 'restored-run',
                'revision': 1,
                'status': 'running',
                'label': '正在调用模型',
                'tools': [
                  {'label': '读取笔记', 'status': 'running'},
                ],
              },
            ],
            'pendingApprovals': [],
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: chat, appearance: appearance, onConnection: () {}),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('正在调用模型'), findsOneWidget);
      expect(find.text('工具 1 项进行中'), findsOneWidget);
      expect(find.byTooltip('停止回复'), findsOneWidget);

      // 模拟远端运行失败结束并写入 lastRun
      api.lastRun = {
        'sessionId': mainSession,
        'runId': 'restored-run',
        'revision': 2,
        'status': 'failed',
        'endedAt': '2026-11-26T00:00:00Z',
      };
      api.frames.add(
        SseFrame(
          event: 'session_status_updated',
          data: {'instanceId': 'test-instance', ...api.lastRun!},
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('上一轮回复未能完成，你可以重新发送或继续对话'),
        findsOneWidget,
      );
      expect(find.byTooltip('发送'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'shows timeout notice even when last saved message is a partial assistant transition',
    (tester) async {
      final api = _PartialTimeoutApi();
      final chat = ChatController(api, () => api);
      final appearance = AppearanceSettings(
        readPalette: () async => null,
        writePalette: (_) async {},
      );
      addTearDown(chat.dispose);
      addTearDown(appearance.dispose);
      chat.start();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: chat, appearance: appearance, onConnection: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('我先去查一下资料。'), findsOneWidget);
      expect(find.text('处理超时，未生成完整回复'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _PartialTimeoutApi extends _ExecutionApi {
  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    if (path == '/api/conversation') {
      return {
        'sessionId': query?['sessionId'],
        'piSessionId': 'binding',
        'revision': 'rev-partial',
        'messages': [
          {
            'id': 'u1',
            'role': 'user',
            'content': '帮我深入调研一下',
            'metadata': {'runId': 'timeout-run'},
          },
          {
            'id': 'assistant-timeout-run',
            'role': 'assistant',
            'content': '我先去查一下资料。',
            'metadata': {'runId': 'timeout-run'},
          },
        ],
        'lastRun': {
          'sessionId': mainSession,
          'runId': 'timeout-run',
          'revision': 5,
          'status': 'failed',
          'label': '处理超时，未生成完整回复',
          'endedAt': '2026-11-26T08:12:23Z',
        },
      };
    }
    return super.get(path, query: query);
  }
}

class _RestoredRunApi extends _ExecutionApi {
  Json? lastRun;

  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    if (path == '/api/conversation') {
      return {
        'sessionId': query?['sessionId'],
        'piSessionId': 'binding',
        'revision': 'rev1',
        'messages': [
          {'id': 'u1', 'role': 'user', 'content': '帮我查一下'},
        ],
        'lastRun': lastRun,
      };
    }
    return super.get(path, query: query);
  }
}
