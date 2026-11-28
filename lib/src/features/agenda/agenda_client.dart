import '../../network/api.dart';
import 'agenda_models.dart';

/// 事项接口适配。
///
/// 只调用服务端契约里已有的端点，写操作失败时不自动重发，交由控制器回读权威状态。
class AgendaClient {
  AgendaClient(this._api);

  final MuseApi _api;

  String? _instanceZone;
  bool _zoneLoaded = false;

  /// 服务端实例的时区。日历归属和写入的时间戳都按此时区解释。
  String? get instanceZone => _instanceZone;

  String _path(String id) => '/api/agenda/items/${Uri.encodeComponent(id)}';

  /// 读取服务端实例时区。读不到时按本机时区处理，页面照常可用。
  Future<void> loadInstanceZone() async {
    if (_zoneLoaded) return;
    try {
      final result = await _api.get('/api/health');
      final zone = result['timeZone'];
      if (zone is String && zone.isNotEmpty) {
        _instanceZone = zone;
        _zoneLoaded = true;
      }
    } catch (_) {
      // 时区只影响展示，读取失败不阻塞事项列表。
    }
  }

  /// 读取事项列表。`to` 是排他边界。
  Future<List<AgendaItem>> list({
    AgendaScope scope = AgendaScope.all,
    String? query,
    DateTime? from,
    DateTime? to,
  }) async {
    await loadInstanceZone();
    final text = query?.trim();
    final result = await _api.get(
      '/api/agenda/items',
      query: {
        'status': scope.status,
        if (text != null && text.isNotEmpty) 'q': text,
        if (from != null) 'from': formatAgendaDate(from),
        if (to != null) 'to': formatAgendaDate(to),
      },
    );
    final items = result['items'];
    if (items is! List) throw const FormatException('Invalid agenda items');
    return items
        .map((item) => AgendaItem.tryParse(item, timeZone: _instanceZone))
        .whereType<AgendaItem>()
        .toList(growable: false);
  }

  /// 读取单个事项。
  Future<AgendaItem> get(String id) async {
    await loadInstanceZone();
    final result = await _api.get(_path(id));
    return AgendaItem.fromJson(_payload(result), timeZone: _instanceZone);
  }

  /// 新建事项。
  Future<AgendaItem> create({
    required String title,
    String? notes,
    Json? schedule,
    Json? due,
    List<Json>? reminders,
  }) async {
    final result = await _api.post('/api/agenda/items', {
      'title': title,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'schedule': ?schedule,
      'due': ?due,
      if (reminders != null && reminders.isNotEmpty) 'reminders': reminders,
    });
    return AgendaItem.fromJson(_payload(result), timeZone: _instanceZone);
  }

  /// 修改事项。只发送真正变化的字段。
  Future<AgendaItem> update(
    String id, {
    String? title,
    String? notes,
    bool clearNotes = false,
    Json? schedule,
    bool clearSchedule = false,
    Json? due,
    bool clearDue = false,
    bool? completed,
    bool? pinned,
  }) async {
    final body = <String, dynamic>{
      'title': ?title,
      if (clearNotes) 'notes': '' else 'notes': ?notes?.trim(),
      if (clearSchedule) 'schedule': null else 'schedule': ?schedule,
      if (clearDue) 'due': null else 'due': ?due,
      'completed': ?completed,
      'pinned': ?pinned,
    };
    if (body.isEmpty) return get(id);
    final result = await _api.patch(_path(id), body);
    return AgendaItem.fromJson(_payload(result), timeZone: _instanceZone);
  }

  /// 新建提醒，返回更新后的事项。
  Future<AgendaItem> addReminder(
    String itemId, {
    required String date,
    String? time,
    String? at,
  }) async {
    final result = await _api.post(
      '${_path(itemId)}/reminders',
      _reminderBody(date: date, time: time, at: at),
    );
    return AgendaItem.fromJson(_payload(result), timeZone: _instanceZone);
  }

  /// 修改提醒，返回更新后的事项。
  Future<AgendaItem> updateReminder(
    String itemId,
    String reminderId, {
    required String date,
    String? time,
    String? at,
  }) async {
    final result = await _api.patch(
      '${_path(itemId)}/reminders/${Uri.encodeComponent(reminderId)}',
      _reminderBody(date: date, time: time, at: at),
    );
    return AgendaItem.fromJson(_payload(result), timeZone: _instanceZone);
  }

  /// 取消提醒，返回更新后的事项。
  Future<AgendaItem> deleteReminder(String itemId, String reminderId) async {
    final result = await _api.delete(
      '${_path(itemId)}/reminders/${Uri.encodeComponent(reminderId)}',
    );
    return AgendaItem.fromJson(_payload(result), timeZone: _instanceZone);
  }

  /// 端点直接返回事项；兼容包一层 `item` 的返回。
  Json _payload(Json result) {
    if (result['id'] is String) return result;
    final item = result['item'];
    if (item is Json) return item;
    throw const FormatException('Invalid agenda item payload');
  }
}

/// 提醒的写入内容。绝对提醒只给日期和可选时刻，由服务端按自身时区解释。
Json _reminderBody({required String date, String? time, String? at}) => {
  'kind': 'absolute',
  if (at != null) 'at': at else 'date': date,
  if (at == null && time != null) 'time': time,
};

/// 把写操作的失败翻译成用户能看懂的提示。
String agendaErrorMessage(Object error) {
  if (error is ApiException) {
    if (error.status == 401) return '登录已失效，请重新连接服务器';
    return switch (error.code) {
      'INVALID_INPUT' => '内容格式无效或超出长度限制',
      'NOT_FOUND' => '事项不存在或已被删除',
      'CONFLICT' => '事项已被其它端修改，请刷新后重试',
      _ => switch (error.status) {
        408 => '请求超时，请稍后重试',
        0 => '无法连接到服务器',
        404 => '事项不存在或已被删除',
        _ => '操作失败，请重试',
      },
    };
  }
  return '操作失败，请重试';
}

/// 写请求的结果是否不确定。
///
/// 这类失败可能是服务端已经写入、只是回执没到，必须回读权威状态，不能重发。
bool isAmbiguousAgendaFailure(Object error) =>
    error is ApiException &&
    (error.status == 0 || error.status == 408 || error.status >= 500);
