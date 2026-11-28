import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_muse_flutter/src/features/chat/chat_controller.dart'
    show mainSession;
import 'package:pi_muse_flutter/src/network/api.dart';

class SessionTestApi extends MuseApi {
  SessionTestApi() : super(Uri.parse('http://localhost'));

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
  Future<Json> delete(String path, [Json? body]) async {
    expect(path, '/api/sessions/topic');
    deletes.add(body!);
    if (deletes.length == 1) {
      throw const ApiException(409, code: 'SESSION_SCHEDULES_CHANGED');
    }
    final receipt = await finalDelete.future;
    topicTitle = null;
    return receipt;
  }
}
