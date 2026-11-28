import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../network/api.dart';
import '../../shared/workspace_events.dart';
import 'agenda_client.dart';
import 'agenda_models.dart';

/// 日程事项的本地状态。
///
/// 列表与日历共用同一份服务端事实：写操作成功后回读权威状态，
/// 结果不确定的失败只回读、不重发。连接级通知里的 `agenda_updated` 让页面失效重读。
class AgendaController extends ChangeNotifier {
  AgendaController({
    required AgendaClient client,
    required Stream<WorkspaceEvent> events,
  }) : _client = client {
    _subscription = events.listen(_onWorkspaceEvent);
  }

  final AgendaClient _client;
  late final StreamSubscription<WorkspaceEvent> _subscription;

  bool _disposed = false;
  bool _running = false;
  bool _dirty = false;

  /// 列表筛选范围。
  AgendaScope scope = AgendaScope.unfinished;

  /// 列表搜索词。
  String query = '';

  /// 选中的日历日；为空时列表显示全部事项。
  DateTime? selectedDay;

  /// 日历显示的月份。
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  /// 列表当前展示的事项。
  List<AgendaItem> items = const [];

  /// 日历月份内的事项。
  List<AgendaItem> monthItems = const [];

  /// 是否正在读取。
  bool loading = false;

  /// 读取失败提示。
  String? error;

  /// 最近一次操作提示。
  String? notice;

  /// 服务端通知引起的失效次数。详情页据此回读权威状态。
  int invalidationCount = 0;

  /// 需要打开的事项 ID。聊天里的事项卡片用它跳到同一个事项。
  String? focusItemId;

  /// 打开事项时是否直接定位到时间设置。
  bool focusTime = false;

  /// 当前月份的第一天。
  DateTime get monthStart => DateTime(month.year, month.month);

  /// 服务端实例的时区。
  String? get instanceZone => _client.instanceZone;

  /// 下个月的第一天，作为查询的排他边界。
  DateTime get nextMonthStart => DateTime(month.year, month.month + 1);

  /// 读取事项列表和当月事项。
  Future<void> refresh() async {
    if (_disposed) return;
    if (_running) {
      _dirty = true;
      return;
    }
    _running = true;
    loading = true;
    error = null;
    _notify();
    try {
      final day = selectedDay;
      // 列表和当月事项并发读取，避免串行等待两轮往返。
      final listFuture = _client.list(
        scope: scope,
        query: query,
        from: day,
        to: day == null ? null : DateTime(day.year, day.month, day.day + 1),
      );
      final calendarFuture = _client.list(
        scope: AgendaScope.all,
        from: monthStart,
        to: nextMonthStart,
      );
      final list = await listFuture;
      final calendar = await calendarFuture;
      if (_disposed) return;
      items = list;
      monthItems = calendar;
    } catch (failure) {
      if (_disposed) return;
      error = agendaErrorMessage(failure);
    } finally {
      _running = false;
      loading = false;
      _notify();
      if (_dirty && !_disposed) {
        _dirty = false;
        unawaited(refresh());
      }
    }
  }

  /// 收到服务端变更通知后重新读取。
  void invalidate() {
    if (_disposed) return;
    unawaited(refresh());
  }

  /// 切换筛选范围。
  Future<void> setScope(AgendaScope value) async {
    if (scope == value) return;
    scope = value;
    _notify();
    await refresh();
  }

  /// 设置搜索词。
  Future<void> setQuery(String value) async {
    final text = value.trim();
    if (query == text) return;
    query = text;
    _notify();
    await refresh();
  }

  /// 选择或取消某一天。
  Future<void> selectDay(DateTime? day) async {
    final next = day == null ? null : DateTime(day.year, day.month, day.day);
    if (selectedDay == next) return;
    selectedDay = next;
    _notify();
    await refresh();
  }

  /// 切换日历月份。
  Future<void> setMonth(DateTime value) async {
    final next = DateTime(value.year, value.month);
    if (month == next) return;
    month = next;
    _notify();
    await refresh();
  }

  /// 读取单个事项。
  Future<AgendaItem?> read(String id) async {
    try {
      return await _client.get(id);
    } catch (failure) {
      if (_disposed) return null;
      notice = agendaErrorMessage(failure);
      _notify();
      return null;
    }
  }

  /// 新建事项。
  Future<AgendaItem?> create({
    required String title,
    String? notes,
    Json? schedule,
    Json? due,
  }) => _write(
    () => _client.create(
      title: title,
      notes: notes,
      schedule: schedule,
      due: due,
    ),
  );

  /// 修改事项。
  Future<AgendaItem?> update(
    String id, {
    String? title,
    String? notes,
    bool clearNotes = false,
    Json? schedule,
    bool clearSchedule = false,
    Json? due,
    bool clearDue = false,
  }) => _write(
    () => _client.update(
      id,
      title: title,
      notes: notes,
      clearNotes: clearNotes,
      schedule: schedule,
      clearSchedule: clearSchedule,
      due: due,
      clearDue: clearDue,
    ),
  );

  /// 置顶或取消置顶。
  Future<AgendaItem?> setPinned(AgendaItem item, bool pinned) =>
      _write(() => _client.update(item.id, pinned: pinned));

  /// 完成或重新打开事项。
  Future<AgendaItem?> setCompleted(AgendaItem item, bool completed) =>
      _write(() => _client.update(item.id, completed: completed));

  /// 新建提醒。
  Future<AgendaItem?> addReminder(
    String itemId, {
    required DateTime day,
    String? time,
  }) => _write(
    () => _client.addReminder(itemId, date: formatAgendaDate(day), time: time),
  );

  /// 修改提醒。
  Future<AgendaItem?> updateReminder(
    String itemId,
    String reminderId, {
    required DateTime day,
    String? time,
  }) => _write(
    () => _client.updateReminder(
      itemId,
      reminderId,
      date: formatAgendaDate(day),
      time: time,
    ),
  );

  /// 取消提醒。
  Future<AgendaItem?> deleteReminder(String itemId, String reminderId) =>
      _write(() => _client.deleteReminder(itemId, reminderId));

  /// 请求打开某个事项。
  ///
  /// [focusTime] 为真时打开后直接定位到时间设置。
  void openItem(String id, [bool focusTime = false]) {
    if (_disposed) return;
    focusItemId = id;
    this.focusTime = focusTime;
    _notify();
  }

  /// 清除打开请求。
  void clearFocus() {
    if (_disposed || focusItemId == null) return;
    focusItemId = null;
    focusTime = false;
    _notify();
  }

  /// 执行写操作。
  ///
  /// 结果不确定时不重发写请求，改为回读权威状态并提示用户核对。
  Future<AgendaItem?> _write(Future<AgendaItem> Function() action) async {
    try {
      final item = await action();
      if (_disposed) return item;
      notice = null;
      _apply(item);
      _notify();
      unawaited(refresh());
      return item;
    } catch (failure) {
      if (_disposed) return null;
      if (isAmbiguousAgendaFailure(failure)) {
        notice = '操作结果未确认，已刷新最新状态，请核对后再操作';
        await refresh();
      } else {
        notice = agendaErrorMessage(failure);
        _notify();
      }
      return null;
    }
  }

  /// 把服务端返回的事项合并进本地列表。
  void _apply(AgendaItem item) {
    items = _replace(items, item);
    monthItems = _replace(monthItems, item);
  }

  List<AgendaItem> _replace(List<AgendaItem> source, AgendaItem item) {
    final index = source.indexWhere((entry) => entry.id == item.id);
    if (index < 0) return [...source, item];
    final next = [...source];
    next[index] = item;
    return next;
  }

  void _onWorkspaceEvent(WorkspaceEvent event) {
    if (_disposed) return;
    // 连接就绪和事项变更都让页面失效，服务端是唯一事实来源。
    if (event.name != 'agenda_updated' && event.name != 'ready') return;
    invalidationCount++;
    invalidate();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
