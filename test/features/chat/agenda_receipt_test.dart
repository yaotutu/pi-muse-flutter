import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/features/chat/chat_controller.dart';
import 'package:pi_muse_flutter/src/features/chat/chat_page.dart';
import 'package:pi_muse_flutter/src/network/api.dart';
import 'package:pi_muse_flutter/src/shared/agenda_receipt.dart';

class _ReceiptTransport extends MuseApi {
  _ReceiptTransport() : super(Uri.parse('http://localhost'));

  final frames = StreamController<SseFrame>();

  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    if (path == '/api/sessions') {
      return {
        'sessions': [
          {'id': mainSession, 'title': '默认会话'},
        ],
      };
    }
    if (path == '/api/conversation') {
      return {
        'sessionId': query?['sessionId'],
        'piSessionId': 'binding',
        'revision': 'revision',
        'messages': const <Json>[],
      };
    }
    return {};
  }

  @override
  Stream<SseFrame> run(Json body) => frames.stream;
}

const _receipt = {
  'id': 'receipt',
  'itemId': 'item',
  'title': '取快递',
  'kind': 'item_created',
  'when': '2026-03-08',
  'timeZone': 'Asia/Shanghai',
};

void main() {
  group('agenda receipt', () {
    test('reads a top-level receipt from an assistant message', () {
      expect(
        agendaReceiptFromMessage({
          'role': 'assistant',
          'agendaReceipt': _receipt,
        })?.id,
        'receipt',
      );
      expect(
        agendaReceiptFromMessage({'role': 'user', 'agendaReceipt': _receipt}),
        isNull,
      );
      expect(agendaReceiptFromMessage({'role': 'assistant'}), isNull);
    });

    test('reads the receipt from a CUSTOM event', () {
      expect(
        agendaReceiptFromEvent({
          'type': 'CUSTOM',
          'name': 'agenda_receipt',
          'value': _receipt,
        })?.id,
        'receipt',
      );
      expect(
        agendaReceiptFromEvent({'type': 'CUSTOM', 'name': 'other'}),
        isNull,
      );
      expect(agendaReceiptFromEvent({'type': 'TEXT_MESSAGE_CONTENT'}), isNull);
    });
  });

  test('the run stream records a live receipt', () async {
    final api = _ReceiptTransport();
    final chat = ChatController(api, () => api)..synchronized = true;
    addTearDown(chat.dispose);
    addTearDown(api.frames.close);
    await chat.refresh(chat.active);
    chat.setDraft('帮我记一下取快递');

    final sending = chat.send();
    api.frames.add(
      const SseFrame(
        data: {'type': 'CUSTOM', 'name': 'agenda_receipt', 'value': _receipt},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(chat.active.liveAgendaReceipts.single.id, 'receipt');

    api.frames.add(const SseFrame(data: {'type': 'RUN_FINISHED'}));
    await api.frames.close();
    await sending;
  });

  testWidgets('the transcript shows one card for a saved and a live receipt', (
    tester,
  ) async {
    final api = _ReceiptTransport();
    final chat = ChatController(api, () => api)..synchronized = true;
    addTearDown(chat.dispose);
    chat.active.revision = 'revision';
    chat.active.dirty = false;
    chat.active.history = [
      ChatMessage(
        'message',
        'assistant',
        '已经记下了',
        agendaReceipt: AgendaReceipt.tryParse(_receipt),
      ),
    ];
    chat.active.addAgendaReceipt(AgendaReceipt.tryParse(_receipt)!);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(chat: chat, onReconnect: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已创建事项'), findsOneWidget);
    expect(find.text('取快递'), findsOneWidget);
    expect(find.text('查看事项'), findsOneWidget);
    expect(find.text('修改时间'), findsOneWidget);
  });

  testWidgets('the card shows the server local time of a UTC timestamp', (
    tester,
  ) async {
    final api = _ReceiptTransport();
    final chat = ChatController(api, () => api)..synchronized = true;
    addTearDown(chat.dispose);
    chat.active.revision = 'revision';
    chat.active.dirty = false;
    chat.active.history = [
      ChatMessage(
        'message',
        'assistant',
        '已经记下了',
        agendaReceipt: AgendaReceipt.tryParse({
          ..._receipt,
          'when': '2026-03-08T01:00:00Z',
        }),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(chat: chat, onReconnect: () {}),
      ),
    );
    await tester.pumpAndSettle();

    // 服务端是上海时间，01:00Z 显示为 09:00，不标成 01:00。
    expect(find.textContaining('09:00'), findsOneWidget);
    expect(find.textContaining('Asia/Shanghai'), findsOneWidget);
    expect(find.textContaining('01:00'), findsNothing);
  });
}
