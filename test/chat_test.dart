import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_muse_flutter/src/api.dart';
import 'package:pi_muse_flutter/src/chat.dart';
import 'package:pi_muse_flutter/src/chat_attachment.dart';

class _Transport implements MuseApi {
  final stream = StreamController<SseFrame>();
  final runStream = StreamController<SseFrame>();
  final submitted = <Json>[];
  final history = <String, List<Json>>{};
  final directory = <String, String>{mainSession: '默认会话', topicId: '专题会话'};
  final sessionWrites = <(String, String, Json)>[];
  Future<Json> Function()? readDirectory;
  Future<Json> Function(String id, Json body)? rename;
  Future<Json> Function(String id, Json body)? remove;

  @override
  Stream<SseFrame> events() => stream.stream;

  @override
  Stream<SseFrame> run(Json body) {
    submitted.add(body);
    return runStream.stream;
  }

  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    if (path == '/api/sessions') {
      return readDirectory == null ? directoryData() : await readDirectory!();
    }
    if (path.endsWith('/schedules')) return _schedules();
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

void main() {
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
      expect(chat.canSend, false);
      expect(chat.active.draftAttachments, isEmpty);
      await chat.verifySubmission();
      expect(chat.active.submission, isNull);
      expect(chat.active.draftAttachments.single, same(original));
      expect(chat.canSend, true);
      expect(api.submitted, hasLength(1));
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
}
