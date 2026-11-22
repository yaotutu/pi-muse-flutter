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
