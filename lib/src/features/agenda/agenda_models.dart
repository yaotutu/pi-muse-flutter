import '../../network/api.dart';
import '../../shared/agenda_moment.dart';

export '../../shared/agenda_moment.dart'
    show
        AgendaMoment,
        agendaTimeInZone,
        formatAgendaDate,
        formatAgendaMoment,
        formatAgendaOffset,
        formatAgendaLocalTimestamp,
        parseAgendaMoment;

/// 事项列表的筛选范围。
enum AgendaScope {
  /// 只看未完成的事项。
  unfinished,

  /// 未完成和已完成都显示。
  all;

  /// 对应服务端 `status` 参数。
  String get status => switch (this) {
    AgendaScope.unfinished => 'open',
    AgendaScope.all => 'all',
  };

  String get label => switch (this) {
    AgendaScope.unfinished => '未完成',
    AgendaScope.all => '全部',
  };
}

/// 事项的安排时间。
class AgendaSchedule {
  const AgendaSchedule({
    required this.type,
    required this.start,
    this.end,
    this.timeZone,
  });

  factory AgendaSchedule.fromJson(Json json, {String? timeZone}) {
    final type = json['type'];
    final start = json['start'];
    if (type is! String || start is! String) {
      throw const FormatException('Invalid agenda schedule');
    }
    final end = json['end'];
    final zone = json['timeZone'];
    return AgendaSchedule(
      type: type,
      start: start,
      end: end is String ? end : null,
      timeZone: zone is String && zone.isNotEmpty ? zone : timeZone,
    );
  }

  /// `date` 表示只有日期，`time` 表示带具体时刻。
  final String type;
  final String start;
  final String? end;
  final String? timeZone;

  bool get dateOnly => type == 'date';

  AgendaMoment? get moment => parseAgendaMoment(start, zoneName: timeZone);

  AgendaMoment? get endMoment => parseAgendaMoment(end, zoneName: timeZone);
}

/// 事项的截止时间。
class AgendaDue {
  const AgendaDue({required this.type, required this.value, this.timeZone});

  factory AgendaDue.fromJson(Json json, {String? timeZone}) {
    final type = json['type'];
    final value = json['value'];
    if (type is! String || value is! String) {
      throw const FormatException('Invalid agenda due');
    }
    final zone = json['timeZone'];
    return AgendaDue(
      type: type,
      value: value,
      timeZone: zone is String && zone.isNotEmpty ? zone : timeZone,
    );
  }

  final String type;
  final String value;
  final String? timeZone;

  bool get dateOnly => type == 'date';

  AgendaMoment? get moment => parseAgendaMoment(value, zoneName: timeZone);
}

/// 提醒的触发方式。
enum AgendaReminderKind {
  /// 指定绝对时间。
  absolute,

  /// 安排时间之前。
  beforeStart,

  /// 截止时间之前。
  beforeDue;

  static AgendaReminderKind? fromJson(String? value) => switch (value) {
    'absolute' => AgendaReminderKind.absolute,
    'before_start' => AgendaReminderKind.beforeStart,
    'before_due' => AgendaReminderKind.beforeDue,
    _ => null,
  };

  String get label => switch (this) {
    AgendaReminderKind.absolute => '指定时间',
    AgendaReminderKind.beforeStart => '安排之前',
    AgendaReminderKind.beforeDue => '截止之前',
  };
}

/// 提醒的触发状态。
enum AgendaReminderStatus {
  pending,
  triggered,
  cancelled;

  static AgendaReminderStatus? fromJson(String? value) => switch (value) {
    'pending' => AgendaReminderStatus.pending,
    'triggered' => AgendaReminderStatus.triggered,
    'cancelled' => AgendaReminderStatus.cancelled,
    _ => null,
  };

  String get label => switch (this) {
    AgendaReminderStatus.pending => '待触发',
    AgendaReminderStatus.triggered => '已触发',
    AgendaReminderStatus.cancelled => '已取消',
  };
}

/// 事项上的一条提醒。
class AgendaReminder {
  const AgendaReminder({
    required this.id,
    required this.kind,
    required this.fireAt,
    required this.status,
    this.triggeredAt,
    this.at,
    this.offsetMinutes,
    this.timeZone,
  });

  factory AgendaReminder.fromJson(Json json, {String? timeZone}) {
    final id = json['id'];
    final kind = json['kind'];
    final fireAt = json['fireAt'];
    final status = json['status'];
    if (id is! String ||
        kind is! String ||
        fireAt is! String ||
        status is! String) {
      throw const FormatException('Invalid agenda reminder');
    }
    final triggeredAt = json['triggeredAt'];
    final at = json['at'];
    final offsetMinutes = json['offsetMinutes'];
    return AgendaReminder(
      id: id,
      kind: kind,
      fireAt: fireAt,
      status: status,
      triggeredAt: triggeredAt is String ? triggeredAt : null,
      at: at is String ? at : null,
      offsetMinutes: offsetMinutes is int ? offsetMinutes : null,
      timeZone: timeZone,
    );
  }

  final String id;
  final String kind;
  final String fireAt;
  final String status;
  final String? triggeredAt;
  final String? at;
  final int? offsetMinutes;

  /// 提醒所属的服务端时区。
  final String? timeZone;

  AgendaReminderKind? get reminderKind => AgendaReminderKind.fromJson(kind);

  AgendaReminderStatus? get reminderStatus =>
      AgendaReminderStatus.fromJson(status);

  AgendaMoment? get moment => parseAgendaMoment(fireAt, zoneName: timeZone);

  bool get pending => status == 'pending';
}

/// 一条事项。
class AgendaItem {
  const AgendaItem({
    required this.id,
    required this.title,
    this.notes,
    this.schedule,
    this.due,
    this.pinnedAt,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
    this.reminders = const [],
  });

  /// 解析事项。字段不完整时返回 null，单条坏数据不影响整页列表。
  ///
  /// [timeZone] 是服务端时区，用于解释没有自带时区的时间取值。
  static AgendaItem? tryParse(Object? value, {String? timeZone}) {
    if (value is! Json) return null;
    final id = value['id'];
    final title = value['title'];
    if (id is! String || title is! String || id.isEmpty) return null;
    final schedule = value['schedule'];
    final due = value['due'];
    final pinnedAt = value['pinnedAt'];
    final completedAt = value['completedAt'];
    final createdAt = value['createdAt'];
    final updatedAt = value['updatedAt'];
    final reminders = value['reminders'];
    return AgendaItem(
      id: id,
      title: title,
      notes: value['notes'] is String ? value['notes'] as String : null,
      schedule: schedule is Json
          ? AgendaSchedule.fromJson(schedule, timeZone: timeZone)
          : null,
      due: due is Json ? AgendaDue.fromJson(due, timeZone: timeZone) : null,
      pinnedAt: pinnedAt is String ? pinnedAt : null,
      completedAt: completedAt is String ? completedAt : null,
      createdAt: createdAt is String ? createdAt : null,
      updatedAt: updatedAt is String ? updatedAt : null,
      reminders: reminders is List
          ? reminders
                .whereType<Json>()
                .map(
                  (reminder) =>
                      AgendaReminder.fromJson(reminder, timeZone: timeZone),
                )
                .toList(growable: false)
          : const [],
    );
  }

  factory AgendaItem.fromJson(Json json, {String? timeZone}) {
    final item = tryParse(json, timeZone: timeZone);
    if (item == null) throw const FormatException('Invalid agenda item');
    return item;
  }

  final String id;
  final String title;
  final String? notes;
  final AgendaSchedule? schedule;
  final AgendaDue? due;
  final String? pinnedAt;
  final String? completedAt;
  final String? createdAt;
  final String? updatedAt;
  final List<AgendaReminder> reminders;

  bool get completed => completedAt != null;

  bool get pinned => pinnedAt != null;

  /// 事项在日历上涉及的所有时间：安排、截止和待触发的提醒。
  List<AgendaMoment> get moments => [
    ?schedule?.moment,
    ?due?.moment,
    for (final reminder in reminders)
      if (reminder.pending) ?reminder.moment,
  ];

  /// 跨日安排的结束时间。
  AgendaMoment? get scheduleEnd => schedule?.endMoment;

  /// 安排时间占用的日历日。跨日安排包含中间的所有日期。
  List<DateTime> scheduleDays({String? instanceZone}) {
    final start = schedule?.moment;
    if (start == null) return const [];
    final first = _dayOf(start, instanceZone);
    final days = <DateTime>[first];
    final end = scheduleEnd;
    if (end != null) {
      final last = _dayOf(end, instanceZone);
      var day = DateTime(first.year, first.month, first.day + 1);
      while (!day.isAfter(last)) {
        days.add(day);
        day = DateTime(day.year, day.month, day.day + 1);
      }
    }
    return days;
  }

  /// 截止时间占用的日历日。
  List<DateTime> dueDays({String? instanceZone}) {
    final moment = due?.moment;
    if (moment == null) return const [];
    return [_dayOf(moment, instanceZone)];
  }

  /// 未取消提醒占用的日历日。
  List<DateTime> reminderDays({String? instanceZone}) {
    final days = <DateTime>[];
    for (final reminder in reminders) {
      if (reminder.reminderStatus == AgendaReminderStatus.cancelled) continue;
      final moment = reminder.moment;
      if (moment == null) continue;
      days.add(_dayOf(moment, instanceZone));
    }
    return days;
  }

  /// 事项涉及的所有日历日。
  ///
  /// 具体时刻按实例时区归属日历日；跨日安排包含中间的所有日期。
  List<DateTime> days({String? instanceZone}) => [
    ...scheduleDays(instanceZone: instanceZone),
    ...dueDays(instanceZone: instanceZone),
    ...reminderDays(instanceZone: instanceZone),
  ];

  /// 时刻所属的日历日。
  ///
  /// 有绝对时刻时按实例时区换算，实例时区未知时用展示用的墙上时间。
  DateTime _dayOf(AgendaMoment moment, String? instanceZone) {
    final instant = moment.instant;
    final zoned = instant == null
        ? null
        : agendaTimeInZone(instant, instanceZone);
    if (zoned != null) return DateTime(zoned.year, zoned.month, zoned.day);
    return DateTime(
      moment.wallClock.year,
      moment.wallClock.month,
      moment.wallClock.day,
    );
  }
}
