import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_muse_flutter/src/api.dart';
import 'package:pi_muse_flutter/src/chat.dart';

class _Transport implements MuseApi {
  final stream = StreamController<SseFrame>();
  final runStream = StreamController<SseFrame>();
  final submitted = <Json>[];
  final history = <String, List<Json>>{};

  @override
  Stream<SseFrame> events() => stream.stream;

  @override
  Stream<SseFrame> run(Json body) {
    submitted.add(body);
    return runStream.stream;
  }

  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    if (path == '/api/sessions') return {'sessions': []};
    if (path == '/api/runs/status') throw const ApiException(404);
    final id = query!['sessionId']!;
    return {
      'sessionId': id,
      'piSessionId': '$id-history',
      'revision': 'empty',
      'messages': history[id] ?? <Json>[],
    };
  }

  @override
  Future<Json> post(String path, Json body) async => {'stopped': true};

  @override
  void close() {}
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);
const topicId = 'e1da5342-a4cc-42db-af18-fb9f3f2cf921';

void main() {
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
      expect(chat.presence.$1, '就绪');
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
      expect(chat.presence.$1, '正在回复');
      expect(chat.active.messages.last.text, 'Answer');
      final submitted = api.submitted.single;
      api.history[mainSession] = [
        {...(submitted['message'] as Json), 'role': 'user'},
        {'id': 'assistant', 'role': 'assistant', 'content': 'Answer'},
      ];
      api.runStream.add(const SseFrame(data: {'type': 'RUN_FINISHED'}));
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
    'a disconnected submission is checked read-only and never replays',
    () async {
      final api = _Transport();
      final chat = ChatController(api, () => api);
      addTearDown(chat.dispose);
      await chat.refresh(chat.active);
      chat.synchronized = true;
      chat.setDraft('Keep me');
      final sending = chat.send();
      await api.runStream.close();
      await sending;
      await _tick();
      expect(chat.active.submission?.settled, false);
      expect(chat.canSend, false);
      expect(chat.active.draft, isEmpty);
      await chat.verifySubmission();
      expect(chat.active.submission, isNull);
      expect(chat.active.draft, 'Keep me');
      expect(chat.canSend, true);
      expect(api.submitted, hasLength(1));
    },
  );
}
