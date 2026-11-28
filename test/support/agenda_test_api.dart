import 'package:pi_muse_flutter/src/features/chat/chat_controller.dart'
    show mainSession;
import 'package:pi_muse_flutter/src/network/api.dart';

/// 测试用的服务端替身，同时提供会话目录、聊天历史和日程接口。
class AgendaTestApi extends MuseApi {
  AgendaTestApi() : super(Uri.parse('http://localhost'));

  /// 服务端保存的事项。
  List<Json> items = [];

  /// 日程列表查询的参数，按调用顺序记录。
  final agendaQueries = <Map<String, String>?>[];

  /// 日程写请求，按调用顺序记录。
  final agendaWrites = <(String, Json?)>[];

  /// 读取日程时抛出的错误。
  Object? agendaReadFailure;

  /// 写入日程时抛出的错误。
  Object? agendaWriteFailure;

  /// 聊天历史里返回的消息。
  List<Json> messages = const [];

  /// 服务端实例时区。
  String healthTimeZone = 'Asia/Shanghai';

  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    if (path == '/api/health') {
      return {
        'ok': true,
        'backend': 'pi',
        'configured': true,
        'timeZone': healthTimeZone,
      };
    }
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
        'messages': messages,
      };
    }
    if (path == '/api/agenda/items') {
      agendaQueries.add(query);
      if (agendaReadFailure != null) throw agendaReadFailure!;
      return {'items': items};
    }
    if (path.startsWith('/api/agenda/items/')) {
      final id = path.substring('/api/agenda/items/'.length);
      final item = items.where((entry) => entry['id'] == id).firstOrNull;
      if (item == null) throw const ApiException(404);
      return item;
    }
    return {};
  }

  @override
  Future<Json> post(String path, [Json? body]) async {
    agendaWrites.add((path, body));
    if (agendaWriteFailure != null) throw agendaWriteFailure!;
    if (path == '/api/agenda/items') {
      final item = <String, dynamic>{
        'id': 'created',
        'title': body?['title'],
        'notes': body?['notes'],
        'schedule': body?['schedule'],
        'due': body?['due'],
        'pinnedAt': null,
        'completedAt': null,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
        'reminders': const <Json>[],
      };
      items = [...items, item];
      return item;
    }
    if (path.endsWith('/reminders')) {
      final id = path.substring('/api/agenda/items/'.length, path.length - 10);
      final item = _require(id);
      final reminder = <String, dynamic>{
        'id': 'reminder',
        'kind': 'absolute',
        'fireAt': '${body?['date']}T${body?['time'] ?? '00:00'}:00Z',
        'status': 'pending',
        'triggeredAt': null,
      };
      return {
        ...item,
        'reminders': [...?item['reminders'] as List<Json>?, reminder],
      };
    }
    return {};
  }

  @override
  Future<Json> patch(String path, Json body) async {
    agendaWrites.add((path, body));
    if (agendaWriteFailure != null) throw agendaWriteFailure!;
    final id = path.substring('/api/agenda/items/'.length);
    final item = _require(id.split('/').first);
    final next = {...item, ...body};
    // 服务端用完成与置顶时间表示状态，替身保持一致。
    if (body['completed'] is bool) {
      next['completedAt'] = body['completed'] == true
          ? '2026-03-01T00:00:00Z'
          : null;
    }
    if (body['pinned'] is bool) {
      next['pinnedAt'] = body['pinned'] == true ? '2026-03-01T00:00:00Z' : null;
    }
    return next;
  }

  @override
  Future<Json> delete(String path, [Json? body]) async {
    agendaWrites.add((path, body));
    if (agendaWriteFailure != null) throw agendaWriteFailure!;
    final parts = path.substring('/api/agenda/items/'.length).split('/');
    return _require(parts.first);
  }

  Json _require(String id) {
    final item = items.where((entry) => entry['id'] == id).firstOrNull;
    if (item == null) throw const ApiException(404);
    return item;
  }
}
