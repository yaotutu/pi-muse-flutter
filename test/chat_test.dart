import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_muse_flutter/src/api.dart';
import 'package:pi_muse_flutter/src/chat.dart';
import 'package:pi_muse_flutter/src/chat_attachment.dart';

class _Transport implements MuseApi {
  final stream = StreamController<SseFrame>();
  final runStreams = [StreamController<SseFrame>()];
  StreamController<SseFrame> get runStream => runStreams.first;
  final submitted = <Json>[];
  final history = <String, List<Json>>{};
  final bindings = <String, String>{};
  final revisions = <String, String>{};
  final stops = <Json>[];
  final feedbackWrites = <(String, Json)>[];
  Future<Json> Function(String id)? readHistory;
  Future<Json> Function(Map<String, String> query)? readRunStatus;
  final reattachStreams = <String, Stream<SseFrame>>{};
  final reattachCalls = <(String, String)>[];
  int eventsCalls = 0;
  Future<Json> Function()? stopResult;
  Future<Json> Function()? feedbackWrite;
  Future<Json> Function(String path, Map<String, String>? query)? feedbackRead;
  final directory = <String, String>{mainSession: '默认会话', topicId: '专题会话'};
  final sessionWrites = <(String, String, Json)>[];
  Future<Json> Function()? readDirectory;
  Future<Json> Function(String id, Json body)? rename;
  Future<Json> Function(String id, Json body)? remove;

  @override
  Stream<SseFrame> events() {
    eventsCalls++;
    return stream.stream;
  }

  @override
  Stream<SseFrame> run(Json body) {
    submitted.add(body);
    return runStreams[submitted.length - 1].stream;
  }

  @override
  Stream<SseFrame> streamRun(String sessionId, String runId) {
    reattachCalls.add((sessionId, runId));
    return reattachStreams[runId] ?? const Stream.empty();
  }

  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    if (path == '/api/sessions') {
      return readDirectory == null ? directoryData() : await readDirectory!();
    }
    if (path.endsWith('/schedules')) return _schedules();
    if (path == '/api/runs/status') {
      if (readRunStatus == null) throw const ApiException(404);
      return await readRunStatus!(query!);
    }
    if (path == '/api/runs') {
      final sessionId = query?['sessionId'] ?? mainSession;
      return {
        'instanceId': 'test-instance',
        'runs': runs[sessionId] ?? <Json>[],
        'hasMore': false,
        'nextCursor': null,
      };
    }
    if (path.endsWith('/feedback')) return await feedbackRead!(path, query);
    final id = query!['sessionId']!;
    return readHistory == null ? historyData(id) : await readHistory!(id);
  }

  final runs = <String, List<Json>>{};

  Json historyData(String id) => {
    'sessionId': id,
    'piSessionId': bindings[id] ?? '$id-history',
    'revision': revisions[id] ?? 'empty',
    'messages': history[id] ?? <Json>[],
  };

  @override
  Future<Json> post(String path, Json body) async {
    expect(path, '/api/conversation/stop');
    stops.add(body);
    return stopResult == null ? {'stopped': true} : await stopResult!();
  }

  @override
  Future<Json> put(String path, Json body) async {
    feedbackWrites.add((path, body));
    return feedbackWrite == null
        ? {'reaction': body['reaction'], 'saved': false, 'comments': []}
        : await feedbackWrite!();
  }

  Json directoryData() => {
    'sessions': [
      for (final entry in directory.entries)
        {'id': entry.key, 'title': entry.value},
    ],
  };

  @override
  Future<Json> patch(String path, Json body) async {
    final id = path.split('/').last;
    sessionWrites.add(('PATCH', id, body));
    if (rename != null) return await rename!(id, body);
    directory[id] = body['title'] as String;
    return {
      'session': {'id': id, 'title': directory[id]},
    };
  }

  @override
  Future<Json> delete(String path, Json body) async {
    final id = path.split('/').last;
    sessionWrites.add(('DELETE', id, body));
    if (remove != null) return await remove!(id, body);
    directory.remove(id);
    return _removed;
  }

  @override
  void close() {}
}

const _removed = {
  'ok': true,
  'removed': {'sessions': 1},
};
const _scheduleRevision =
    '0000000000000000000000000000000000000000000000000000000000000000';
Json _schedules() => {
  'scheduleRevision': _scheduleRevision,
  'jobs': [],
  'monitors': [],
};

Future<void> _tick() => Future<void>.delayed(Duration.zero);
const topicId = 'e1da5342-a4cc-42db-af18-fb9f3f2cf921';

Json _reply(String? reaction, {bool saved = false}) => {
  'id': 'answer',
  'role': 'assistant',
  'content': '<think>Private reasoning</think>One\nTwo',
  'metadata': {'source': 'chat', 'feedbackAvailable': true},
  'feedback': {'reaction': reaction, 'saved': saved, 'comments': []},
};

const _ready = SseFrame(
  event: 'ready',
  data: {
    'instanceId': 'test-instance',
    'sessionStatuses': [],
    'pendingApprovals': [],
  },
);

SseFrame _status(Json submitted, int revision, String status) => SseFrame(
  event: 'session_status_updated',
  data: {
    'instanceId': 'test-instance',
    'sessionId': submitted['sessionId'],
    'runId': submitted['runId'],
    'revision': revision,
    'status': status,
  },
);

void main() {
  test(
    'execution details recover a missed terminal run and clear it on restart',
    () async {
      final api = _Transport();
      final first = _Transport();
      final second = _Transport();
      final replacement = _Transport();
      final notifications = [first, second, replacement].iterator;
      final chat = ChatController(api, () {
        notifications.moveNext();
        return notifications.current;
      });
      addTearDown(chat.dispose);
      final terminal = Completer<Json>();
      api.readRunStatus = (query) {
        expect(query, {'sessionId': mainSession, 'runId': 'external'});
        return terminal.future;
      };
      final run = {'sessionId': mainSession, 'runId': 'external'};
      chat.start();
      first.stream.add(_ready);
      first.stream.add(_status(run, 1, 'running'));
      await _tick();
      expect(chat.executionRuns(mainSession).single['status'], 'running');
      chat.reconnect();
      expect(chat.executionRuns(mainSession), isEmpty);
      second.stream.add(_ready);
      await _tick();
      terminal.complete({
        'instanceId': 'test-instance',
        'status': _status(run, 2, 'succeeded').data,
      });
      await _tick();
      expect(chat.executionRuns(mainSession).single['status'], 'succeeded');
      expect(chat.executionRuns(topicId), isEmpty);
      chat.reconnect();
      replacement.stream.add(
        const SseFrame(
          event: 'ready',
          data: {
            'instanceId': 'replacement',
            'sessionStatuses': [],
            'pendingApprovals': [],
          },
        ),
      );
      await _tick();
      expect(chat.executionRuns(mainSession), isEmpty);
    },
  );

  test(
    'feedback keeps its confirmed state until an ambiguous write is checked',
    () async {
      final api = _Transport()..history[mainSession] = [_reply('like')];
      final chat = ChatController(api, () => api)..synchronized = true;
      addTearDown(chat.dispose);
      final conversation = chat.active;
      await chat.refresh(conversation);
      final binding = conversation.binding!;
      final receipt = Completer<Json>();
      api.feedbackWrite = () => receipt.future;
      final changing = chat.changeSaved(conversation, binding, 'answer', true);
      final failure = expectLater(changing, throwsA(isA<ApiException>()));
      expect(conversation.feedbackState('answer'), FeedbackRequestState.busy);
      expect(conversation.history.single.saved, isFalse);
      await chat.changeReaction(
        conversation,
        binding,
        'answer',
        MessageReaction.like,
      );
      receipt.completeError(const ApiException(408));
      await failure;
      expect(conversation.history.single.reaction, MessageReaction.like);
      expect(conversation.history.single.saved, isFalse);
      expect(
        conversation.feedbackState('answer'),
        FeedbackRequestState.unconfirmed,
      );
      await chat.changeSaved(conversation, binding, 'answer', true);
      final (savedPath, savedBody) = api.feedbackWrites.single;
      expect(savedPath, '/api/sessions/main/messages/answer/feedback/saved');
      expect(savedBody, {'piSessionId': binding, 'saved': true});
      api.feedbackRead = (path, query) async {
        expect(path, '/api/sessions/main/messages/answer/feedback');
        expect(query, {'piSessionId': binding});
        return {'reaction': 'dislike', 'saved': true, 'comments': []};
      };
      await chat.verifyFeedback(conversation, binding, 'answer');
      expect(conversation.history.single.reaction, MessageReaction.dislike);
      expect(conversation.history.single.saved, isTrue);
      api.feedbackWrite = () async => {
        'reaction': null,
        'saved': true,
        'comments': [],
      };
      await chat.changeReaction(
        conversation,
        binding,
        'answer',
        MessageReaction.dislike,
      );
      final (path, body) = api.feedbackWrites.last;
      expect(path, '/api/sessions/main/messages/answer/feedback/reaction');
      expect(body, {'piSessionId': binding, 'reaction': null});
      expect(conversation.history.single.reaction, isNull);
      expect(conversation.history.single.saved, isTrue);
      expect(conversation.feedbackState('answer'), isNull);
    },
  );

  test(
    'feedback receipt invalidates older history but yields to a fresh read',
    () async {
      final api = _Transport()..history[mainSession] = [_reply(null)];
      final chat = ChatController(api, () => api)..synchronized = true;
      addTearDown(chat.dispose);
      final conversation = chat.active;
      await chat.refresh(conversation);
      final stale = Completer<Json>();
      final before = api.historyData(mainSession);
      var reads = 0;
      api.readHistory = (id) async =>
          ++reads == 1 ? stale.future : api.historyData(id);
      final refreshing = chat.refresh(conversation);
      await chat.changeReaction(
        conversation,
        conversation.binding!,
        'answer',
        MessageReaction.like,
      );
      expect(conversation.history.single.reaction, MessageReaction.like);
      api.history[mainSession] = [_reply('dislike', saved: true)];
      stale.complete(before);
      await refreshing;
      expect(reads, 2);
      expect(conversation.history.single.reaction, MessageReaction.dislike);
      expect(conversation.history.single.saved, isTrue);
    },
  );

  test(
    'a saved conflict refreshes history and rejects the old binding',
    () async {
      final api = _Transport()..history[mainSession] = [_reply('like')];
      final chat = ChatController(api, () => api)..synchronized = true;
      addTearDown(chat.dispose);
      final conversation = chat.active;
      await chat.refresh(conversation);
      final oldBinding = conversation.binding!;
      api.feedbackWrite = () async {
        api.bindings[mainSession] = 'reset-history';
        api.history[mainSession] = [_reply(null, saved: true)];
        throw const ApiException(409, code: 'SESSION_CONFLICT');
      };
      await expectLater(
        chat.changeSaved(conversation, oldBinding, 'answer', true),
        throwsA(isA<ApiException>()),
      );
      expect(conversation.binding, 'reset-history');
      expect(conversation.history.single.reaction, isNull);
      expect(conversation.history.single.saved, isTrue);
      expect(conversation.feedbackState('answer'), isNull);
      await chat.changeSaved(conversation, oldBinding, 'answer', false);
      expect(api.feedbackWrites, hasLength(1));
    },
  );

  test('history requires a boolean saved field on feedback', () {
    final message = _reply('like', saved: true);
    expect(ChatMessage.fromJson(message).saved, isTrue);
    (message['feedback'] as Json)['saved'] = 'true';
    expect(() => ChatMessage.fromJson(message), throwsFormatException);
  });

  test(
    'quotes keep visible lines and a failed send preserves both drafts',
    () async {
      final api = _Transport()..history[mainSession] = [_reply(null)];
      final chat = ChatController(
        api,
        () => api,
        attachmentPicker: ({required maxFiles, required maxBytes}) async => [
          PickedAttachment('memo.txt', 'text/plain', utf8.encode('notes')),
        ],
      )..synchronized = true;
      addTearDown(chat.dispose);
      final conversation = chat.active;
      await chat.refresh(conversation);
      expect(
        chat.quoteMessage(conversation, conversation.binding, 'answer'),
        true,
      );
      await chat.send();
      expect(api.submitted, isEmpty);
      chat.setDraft('x' * maxChatMessageLength);
      await chat.send();
      expect(api.submitted, isEmpty);
      expect(conversation.quote!.excerpt, 'One\nTwo');
      await chat.chooseAttachments();
      final attachment = conversation.draftAttachments.single;
      chat.setDraft('Follow up');
      final sending = chat.send();
      expect(api.submitted.single['message'], {
        'id': conversation.submission!.message.id,
        'content': '> 助手回复\n> One\n> Two\n\nFollow up',
        'attachments': [attachment.toRequest()],
      });
      chat.setDraft('Newer draft');
      final followUp = chat.stopAndSend();
      api.runStream.add(
        const SseFrame(data: {'type': 'RUN_ERROR', 'code': 'STOPPED'}),
      );
      await api.runStream.close();
      await sending;
      await followUp;
      expect(api.submitted, hasLength(1));
      expect(conversation.draft, 'Newer draft');
      expect(conversation.hasRecoveredDraft, true);
      chat.recoverDraft();
      expect(conversation.draft, 'Follow up');
      expect(conversation.quote!.excerpt, 'One\nTwo');
      expect(conversation.draftAttachments.single, same(attachment));
      chat.recoverDraft();
      expect(conversation.draft, 'Newer draft');
      expect(conversation.quote, isNull);
    },
  );

  for (final stopFirst in [true, false]) {
    test(
      'follow-up uses the original session and a fresh revision (stop first: $stopFirst)',
      () async {
        final api = _Transport();
        final events = _Transport();
        final secondRun = StreamController<SseFrame>();
        api.runStreams.add(secondRun);
        final receipt = Completer<Json>();
        api.stopResult = () => receipt.future;
        final chat = ChatController(api, () => events)..start();
        addTearDown(chat.dispose);
        events.stream.add(_ready);
        await _tick();
        chat.setDraft('First message');
        final first = chat.send();
        final submitted = api.submitted.single;
        events.stream.add(_status(submitted, 1, 'running'));
        await _tick();
        chat.setDraft('Second message');
        final second = chat.stopAndSend();
        await chat.stopAndSend();
        expect(api.stops.single, {
          'sessionId': mainSession,
          'runId': submitted['runId'],
        });
        chat.select(topicId);
        chat.setDraft('Other session draft');
        if (stopFirst) receipt.complete({'stopped': true});
        api.history[mainSession] = [
          {...(submitted['message'] as Json), 'role': 'user'},
        ];
        api.revisions[mainSession] = 'after-first';
        // EOF 和已经保存的消息本身不足以确认运行已结束。
        await api.runStream.close();
        await first;
        await _tick();
        expect(api.submitted, hasLength(1));
        events.stream.add(_status(submitted, 2, 'cancelled'));
        await _tick();
        if (!stopFirst) {
          expect(api.submitted, hasLength(1));
          receipt.complete({'stopped': true});
          await _tick();
        }
        expect(api.submitted, hasLength(2));
        final next = api.submitted.last;
        expect(next['sessionId'], mainSession);
        expect(next['expectedRevision'], 'after-first');
        expect((next['message'] as Json)['content'], 'Second message');
        expect(chat.active.draft, 'Other session draft');
        await secondRun.close();
        await second;
        await events.stream.close();
      },
    );
  }

  for (final outcome in ['false receipt', 'disconnect', 'reset', 'delete']) {
    test('follow-up is cancelled on $outcome', () async {
      final api = _Transport();
      final events = _Transport();
      final receipt = Completer<Json>();
      api.stopResult = () => receipt.future;
      final chat = ChatController(api, () => events)..start();
      addTearDown(chat.dispose);
      events.stream.add(_ready);
      await _tick();
      chat.select(topicId);
      final conversation = chat.active;
      await chat.refresh(conversation);
      chat.setDraft('First message');
      final first = chat.send();
      final submitted = api.submitted.single;
      chat.setDraft('Second message');
      final second = chat.stopAndSend();
      api.history[topicId] = [
        {...(submitted['message'] as Json), 'role': 'user'},
      ];
      if (outcome == 'disconnect') await events.stream.close();
      if (outcome == 'delete') {
        await chat.deleteSession(
          topicId,
          SessionSchedules.fromJson(_schedules()),
          SessionScheduleDisposition.delete,
        );
      }
      if (outcome == 'reset') {
        api.bindings[topicId] = 'reset-binding';
        api.history[topicId] = [];
      }
      receipt.complete({'stopped': outcome != 'false receipt'});
      api.runStream.add(
        const SseFrame(data: {'type': 'RUN_ERROR', 'code': 'STOPPED'}),
      );
      await api.runStream.close();
      await first;
      await second;
      await _tick();
      expect(api.submitted, hasLength(1));
      expect(conversation.waitingToSend, false);
      if (outcome != 'delete') {
        expect(conversation.draft, outcome == 'reset' ? '' : 'Second message');
      }
      if (outcome != 'disconnect') await events.stream.close();
    });
  }

  test('rename keeps history and draft and rejects changes to main', () async {
    final api = _Transport();
    final chat = ChatController(api, () => api)..synchronized = true;
    addTearDown(chat.dispose);
    api.history[topicId] = [
      {'id': 'assistant', 'role': 'assistant', 'content': 'History'},
    ];
    await chat.refreshDirectory();
    chat.select(topicId);
    final original = chat.active;
    await chat.refresh(original);
    chat.setDraft('Keep the draft');
    expect(
      await chat.renameSession(topicId, ' 新标题 '),
      SessionChangeResult.confirmed,
    );
    expect(chat.sessionEntry(topicId)?.title, '新标题');
    expect(chat.active, same(original));
    expect(chat.active.history.single.text, 'History');
    expect(chat.active.draft, 'Keep the draft');
    await expectLater(
      chat.renameSession(mainSession, 'Invalid'),
      throwsFormatException,
    );
    await expectLater(
      chat.deleteSession(
        mainSession,
        SessionSchedules.fromJson(_schedules()),
        SessionScheduleDisposition.delete,
      ),
      throwsFormatException,
    );
    final (method, id, body) = api.sessionWrites.single;
    expect((method, id), ('PATCH', topicId));
    expect(body, {'title': '新标题'});
  });

  test('rename verifies via a fresh directory after a lost response', () async {
    final api = _Transport();
    final chat = ChatController(api, () => api)..synchronized = true;
    addTearDown(chat.dispose);
    await chat.refreshDirectory();
    final stale = Completer<Json>();
    final old = api.directoryData();
    var reads = 0;
    api.readDirectory = () async =>
        ++reads == 1 ? stale.future : api.directoryData();
    final refresh = chat.refreshDirectory();
    api.rename = (id, body) async {
      api.directory[id] = body['title'] as String;
      throw const ApiException(408);
    };
    final renaming = chat.renameSession(topicId, 'Saved upstream');
    await _tick();
    stale.complete(old);
    expect(await refresh, true);
    expect(await renaming, SessionChangeResult.confirmed);
    expect(chat.sessionEntry(topicId)?.title, 'Saved upstream');
    expect(api.sessionWrites, hasLength(1));
  });

  test(
    'deleting the active topic restores the main draft and drops late picks',
    () async {
      final api = _Transport();
      final pick = Completer<List<PickedAttachment>>();
      final chat = ChatController(
        api,
        () => api,
        attachmentPicker: ({required maxFiles, required maxBytes}) =>
            pick.future,
      )..synchronized = true;
      addTearDown(chat.dispose);
      final main = chat.active;
      chat.setDraft('Main draft');
      await chat.refreshDirectory();
      chat.select(topicId);
      final topic = chat.active;
      await chat.refresh(topic);
      final choosing = chat.chooseAttachments();
      final preview = await chat.readSessionSchedules(topicId);
      expect(
        await chat.deleteSession(
          topicId,
          preview,
          SessionScheduleDisposition.delete,
        ),
        SessionChangeResult.confirmed,
      );
      pick.complete([
        PickedAttachment('notes.txt', null, utf8.encode('notes')),
      ]);
      await choosing;
      expect(chat.active, same(main));
      expect(chat.active.draft, 'Main draft');
      expect(chat.sessionEntry(topicId), isNull);
      expect(chat.conversations[topicId], isNull);
      expect(topic.draftAttachments, isEmpty);
      final (method, id, body) = api.sessionWrites.single;
      expect((method, id), ('DELETE', topicId));
      expect(body, {
        'scheduleRevision': _scheduleRevision,
        'scheduleDisposition': 'delete',
      });
    },
  );

  test(
    'uncertain deletion keeps the draft and uses read-only verification',
    () async {
      final api = _Transport();
      final chat = ChatController(api, () => api)..synchronized = true;
      addTearDown(chat.dispose);
      await chat.refreshDirectory();
      chat.select(topicId);
      chat.setDraft('Topic draft');
      final topic = chat.active;
      final preview = await chat.readSessionSchedules(topicId);
      api.remove = (_, _) async => throw const ApiException(502);
      api.readDirectory = () async => throw const ApiException(408);
      expect(
        await chat.deleteSession(
          topicId,
          preview,
          SessionScheduleDisposition.moveToMain,
        ),
        SessionChangeResult.unknown,
      );
      expect(
        await chat.verifySessionChange(topicId),
        SessionChangeResult.unknown,
      );
      expect(topic.draft, 'Topic draft');
      expect(
        chat.pendingSessionDeletion(topicId),
        SessionScheduleDisposition.moveToMain,
      );
      expect(chat.canSend, false);
      await expectLater(
        chat.deleteSession(topicId, preview, SessionScheduleDisposition.delete),
        throwsFormatException,
      );
      chat.select(mainSession);
      chat.setDraft('Other draft');
      api.directory.remove(topicId);
      api.readDirectory = null;
      expect(
        await chat.verifySessionChange(topicId),
        SessionChangeResult.confirmed,
      );
      expect(chat.activeId, mainSession);
      expect(chat.active.draft, 'Other draft');
      expect(chat.conversations[topicId], isNull);
      expect(api.sessionWrites, hasLength(1));
    },
  );

  test(
    'switching conversations keeps drafts and the original active run',
    () async {
      final api = _Transport();
      final events = _Transport();
      final chat = ChatController(api, () => events);
      addTearDown(chat.dispose);
      chat.start();
      events.stream.add(
        const SseFrame(
          event: 'ready',
          data: {
            'instanceId': 'test-instance',
            'sessionStatuses': [],
            'pendingApprovals': [],
          },
        ),
      );
      await _tick();
      expect(chat.activityLabel, isNull);
      chat.setDraft('Main message');
      final completed = chat.send();
      chat.select(topicId);
      chat.setDraft('Topic draft');
      api.runStream.add(
        const SseFrame(
          data: {
            'type': 'TEXT_MESSAGE_CONTENT',
            'messageId': 'assistant',
            'delta': 'Answer',
          },
        ),
      );
      await _tick();
      expect(chat.active.draft, 'Topic draft');
      expect(chat.active.messages, isEmpty);
      chat.select(mainSession);
      expect(chat.activityLabel, '正在回复');
      expect(chat.active.messages.last.text, 'Answer');
      final submitted = api.submitted.single;
      api.history[mainSession] = [
        {...(submitted['message'] as Json), 'role': 'user'},
        {'id': 'assistant', 'role': 'assistant', 'content': 'Answer'},
      ];
      api.runStream.add(
        SseFrame(
          data: {
            'type': 'RUN_FINISHED',
            'sessionId': mainSession,
            'runId': submitted['runId'],
          },
        ),
      );
      await api.runStream.close();
      await completed;
      await _tick();
      expect(chat.active.submission, isNull);
      expect(chat.active.messages.map((message) => message.text), [
        'Main message',
        'Answer',
      ]);
      chat.select(topicId);
      expect(chat.active.draft, 'Topic draft');
      await events.stream.close();
    },
  );

  test(
    'a disconnected submission auto-reconciles read-only and never replays',
    () async {
      final api = _Transport();
      final statusCheck = Completer<Json>();
      api.readRunStatus = (_) => statusCheck.future;
      final chat = ChatController(
        api,
        () => api,
        attachmentPicker: ({required maxFiles, required maxBytes}) async => [
          PickedAttachment('memo.txt', 'text/plain', utf8.encode('notes')),
        ],
      );
      addTearDown(chat.dispose);
      await chat.refresh(chat.active);
      chat.synchronized = true;
      await chat.chooseAttachments();
      final original = chat.active.draftAttachments.single;
      final sending = chat.send();
      final pending = chat.active.messages.single;
      expect(pending.text, isEmpty);
      expect(pending.attachments.single, same(original));
      expect(api.submitted.single['message'], {
        'id': pending.id,
        'content': '',
        'attachments': [original.toRequest()],
      });
      await api.runStream.close();
      await sending;
      await _tick();
      expect(chat.active.submission?.settled, false);
      expect(chat.active.submission?.reconciling, true);
      expect(chat.canSend, false);
      expect(chat.active.draftAttachments, isEmpty);
      // 离线核对失败后停留在待同步，手动核对确认 404 后无损恢复草稿与附件。
      statusCheck.completeError(const ApiException(0));
      await _tick();
      expect(chat.active.submission?.reconciling, false);
      api.readRunStatus = null;
      await chat.verifySubmission();
      expect(chat.active.submission, isNull);
      expect(chat.active.draftAttachments.single, same(original));
      expect(chat.canSend, true);
      expect(api.submitted, hasLength(1));
    },
  );

  test(
    'disconnecting while server keeps running auto-reattaches stream without duplicating text',
    () async {
      final api = _Transport();
      final events = _Transport();
      final events2 = _Transport();
      final reattach = StreamController<SseFrame>();
      final transports = [events, events2, events2].iterator;
      final chat = ChatController(api, () {
        transports.moveNext();
        return transports.current;
      })..start();
      addTearDown(chat.dispose);
      events.stream.add(_ready);
      await _tick();

      chat.setDraft('Long task');
      final sending = chat.send();
      final submitted = api.submitted.single;
      final runId = submitted['runId'] as String;
      final msgId = (submitted['message'] as Json)['id'] as String;
      events2.reattachStreams[runId] = reattach.stream;

      api.runStream.add(
        const SseFrame(
          data: {
            'type': 'TEXT_MESSAGE_CONTENT',
            'messageId': 'assistant-1',
            'delta': 'Hello',
          },
        ),
      );
      await _tick();
      // 模拟手机切后台断流，同时 /api/events 断开
      await events.stream.close();
      await _tick();
      await api.runStream.close();
      await sending;
      expect(chat.active.submission?.reconciling, true);
      expect(chat.active.error, isNull);

      // 回前台重连拿到 ready：服务端仍报告该 run 在运行
      chat.onAppResumed(const Duration(seconds: 10));
      api.history[mainSession] = [
        {'id': msgId, 'role': 'user', 'content': 'Long task'},
      ];
      events2.stream.add(
        SseFrame(
          event: 'ready',
          data: {
            'instanceId': 'test-instance',
            'sessionStatuses': [
              {
                'sessionId': mainSession,
                'runId': runId,
                'revision': 2,
                'source': 'chat',
                'status': 'running',
                'label': '正在思考',
              },
            ],
            'pendingApprovals': [],
          },
        ),
      );
      await _tick();
      expect(chat.active.submission, isNull);
      expect(events2.reattachCalls, [(mainSession, runId)]);

      // 重挂流首帧先补发已缓冲全量快照，后续再增量，不能重复拼接
      reattach.add(
        const SseFrame(
          data: {
            'type': 'TEXT_MESSAGE_CONTENT',
            'messageId': 'assistant-1',
            'delta': 'Hello world',
          },
        ),
      );
      reattach.add(
        const SseFrame(
          data: {
            'type': 'TEXT_MESSAGE_CONTENT',
            'messageId': 'assistant-1',
            'delta': '!',
          },
        ),
      );
      await _tick();
      expect(
        chat.active.messages.map((m) => m.text).toList(),
        ['Long task', 'Hello world!'],
      );

      api.history[mainSession] = [
        {'id': msgId, 'role': 'user', 'content': 'Long task'},
        {'id': 'assistant-1', 'role': 'assistant', 'content': 'Hello world!'},
      ];
      events2.stream.add(
        SseFrame(
          event: 'session_status_updated',
          data: {
            'instanceId': 'test-instance',
            'sessionId': mainSession,
            'runId': runId,
            'revision': 3,
            'source': 'chat',
            'status': 'succeeded',
            'endedAt': '2026-11-26T00:00:00Z',
          },
        ),
      );
      reattach.add(
        SseFrame(
          data: {'type': 'RUN_FINISHED', 'sessionId': mainSession, 'runId': runId},
        ),
      );
      await reattach.close();
      await _tick();
      expect(chat.active.error, isNull);
      expect(
        chat.active.messages.map((m) => m.text).toList(),
        ['Long task', 'Hello world!'],
      );
      await events2.stream.close();
    },
  );

  test(
    'disconnecting when server already finished reconciles cleanly without errors',
    () async {
      final api = _Transport();
      final chat = ChatController(api, () => api)..synchronized = true;
      addTearDown(chat.dispose);
      await chat.refresh(chat.active);
      chat.setDraft('Quick task');
      final sending = chat.send();
      final submitted = api.submitted.single;
      final runId = submitted['runId'] as String;
      final msgId = (submitted['message'] as Json)['id'] as String;
      api.readRunStatus = (query) async => {
        'instanceId': 'test-instance',
        'status': {
          'sessionId': mainSession,
          'runId': runId,
          'revision': 2,
          'source': 'chat',
          'status': 'succeeded',
          'endedAt': '2026-11-26T00:00:00Z',
        },
      };
      api.history[mainSession] = [
        {'id': msgId, 'role': 'user', 'content': 'Quick task'},
        {'id': 'a1', 'role': 'assistant', 'content': 'Done in background'},
      ];
      await api.runStream.close();
      await sending;
      await _tick();
      expect(chat.active.submission, isNull);
      expect(chat.active.error, isNull);
      expect(
        chat.active.messages.map((m) => m.text).toList(),
        ['Quick task', 'Done in background'],
      );
    },
  );

  test(
    'cold start attaches to active server run and can stop it, and brief resume keeps stream',
    () async {
      final api = _Transport();
      final events = _Transport();
      final reattach = StreamController<SseFrame>();
      events.reattachStreams['remote-run'] = reattach.stream;
      final chat = ChatController(api, () => events)..start();
      addTearDown(chat.dispose);

      events.stream.add(
        const SseFrame(
          event: 'ready',
          data: {
            'instanceId': 'test-instance',
            'sessionStatuses': [
              {
                'sessionId': mainSession,
                'runId': 'remote-run',
                'revision': 1,
                'source': 'chat',
                'status': 'running',
                'label': '正在调用工具',
              },
            ],
            'pendingApprovals': [],
          },
        ),
      );
      await _tick();
      expect(events.eventsCalls, 1);
      expect(events.reattachCalls, [(mainSession, 'remote-run')]);
      expect(chat.canStop(sendNext: false), isTrue);

      // 短暂切回前台且长连接仍健康：不重连 /api/events
      chat.onAppResumed(const Duration(seconds: 2));
      await _tick();
      expect(events.eventsCalls, 1);

      await chat.stop();
      expect(api.stops.single, {'sessionId': mainSession, 'runId': 'remote-run'});

      // 切后台超过阈值时重连
      chat.onAppResumed(const Duration(seconds: 8));
      expect(events.eventsCalls, 2);

      await reattach.close();
      await events.stream.close();
    },
  );

  test('selection returns to its original conversation', () async {
    final api = _Transport();
    final pick = Completer<List<PickedAttachment>>();
    final chat = ChatController(
      api,
      () => api,
      attachmentPicker: ({required maxFiles, required maxBytes}) {
        expect(maxFiles, maxChatAttachments);
        expect(maxBytes, maxChatAttachmentBytes);
        return pick.future;
      },
    );
    addTearDown(chat.dispose);
    await chat.refresh(chat.active);
    chat.synchronized = true;
    final selecting = chat.chooseAttachments();
    expect(chat.canSend, false);
    chat.select(topicId);
    await chat.refresh(chat.active);
    expect(chat.canPickAttachments, false);
    pick.complete([PickedAttachment('notes.md', null, utf8.encode('# Hello'))]);
    await selecting;
    expect(chat.active.draftAttachments, isEmpty);
    chat.select(mainSession);
    final attachment = chat.active.draftAttachments.single;
    expect(attachment.name, 'notes.md');
    chat.removeDraftAttachment(attachment.id);
    expect(chat.active.draftAttachments, isEmpty);
  });

  test('invalid attachments leave the original selection intact', () {
    final original = appendChatAttachments([], [
      PickedAttachment('notes.md', null, utf8.encode('# Hello')),
    ], () => 'first');
    for (final file in [
      PickedAttachment('broken.txt', 'text/plain', Uint8List.fromList([0xff])),
      PickedAttachment('fake.png', 'image/png', utf8.encode('text')),
      PickedAttachment('book.pdf', 'application/pdf', utf8.encode('%PDF')),
      PickedAttachment(
        'large.txt',
        'text/plain',
        Uint8List(maxChatAttachmentTextBytes),
      ),
    ]) {
      expect(
        () => appendChatAttachments(original, [file], () => 'extra'),
        throwsA(isA<AttachmentException>()),
      );
    }
    expect(
      original.single.toRequest()['dataBase64'],
      base64Encode(utf8.encode('# Hello')),
    );
  });

  test('image history accepts previews with a different size and MIME', () {
    final webp = Uint8List.fromList([
      82,
      73,
      70,
      70,
      0,
      0,
      0,
      0,
      87,
      69,
      66,
      80,
    ]);
    final image = ChatAttachment.fromJson({
      'id': 'original',
      'name': 'photo.png',
      'kind': 'image',
      'mimeType': 'image/png',
      'size': 8192,
      'image': {'mimeType': 'image/webp', 'dataBase64': base64Encode(webp)},
    });
    expect(image.size, 8192);
    expect(image.imageBytes, webp);
  });

  test(
    'ChatController hydrates runsById from /api/runs and preserves runId across feedback updates',
    () async {
      final api = _Transport()
        ..history[mainSession] = [
          {
            'id': 'a1',
            'role': 'assistant',
            'content': '已查好',
            'metadata': {'runId': 'run-123', 'feedbackAvailable': true},
            'feedback': {'reaction': null, 'saved': false, 'comments': []},
          },
        ]
        ..runs[mainSession] = [
          {
            'sessionId': mainSession,
            'runId': 'run-123',
            'revision': 2,
            'status': 'succeeded',
            'steps': [
              {
                'id': 's1',
                'parentId': null,
                'kind': 'tool',
                'title': '查询当前时间',
                'detail': null,
                'status': 'succeeded',
                'result': '已完成',
                'toolName': 'currentTime',
                'approvalId': null,
                'startedAt': '2026-01-01T00:00:00.000Z',
                'endedAt': '2026-01-01T00:00:01.000Z',
              },
            ],
          },
        ];
      final chat = ChatController(api, () => api)..synchronized = true;
      addTearDown(chat.dispose);
      await chat.refresh(chat.active);
      await _tick();

      final msg = chat.active.history.single;
      expect(msg.runId, 'run-123');
      expect(chat.stepsOf(chat.runForMessage(mainSession, msg)).single['title'], '查询当前时间');

      await chat.changeReaction(chat.active, chat.active.binding!, 'a1', MessageReaction.like);
      final updated = chat.active.history.single;
      expect(updated.reaction, MessageReaction.like);
      expect(updated.runId, 'run-123');
      expect(chat.stepsOf(chat.runForMessage(mainSession, updated)).length, 1);
    },
  );
}
