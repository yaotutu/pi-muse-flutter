import 'package:material_ui/material_ui.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

/// 日程时间。
///
/// 服务端按自身配置的时区保存，客户端不再询问时区。取值分三种：
///
/// - 只有日期：按日历日显示，不做换算。
/// - 带偏移的时间戳：按服务端写下的墙上时间显示，并标出该偏移。
/// - UTC 时间戳：换算到展示时区后再显示。展示时区优先用服务端给的 IANA 时区，
///   服务端时区无法解析时退回本机时区，并明确标出是本机时间。
class AgendaMoment {
  const AgendaMoment({
    required this.wallClock,
    required this.dateOnly,
    this.instant,
    this.offset,
    this.zoneName,
    this.deviceZone = false,
  });

  /// 展示用的年月日和钟点。用 UTC 承载服务端字段，避免设备夏令时调整钟点。
  final DateTime wallClock;

  /// 是否只有日期，没有具体时刻。
  final bool dateOnly;

  /// 这段时间对应的绝对时刻。只有日期的取值没有绝对时刻。
  final DateTime? instant;

  /// 展示时间对应的时区偏移。
  final Duration? offset;

  /// 服务端给出的时区名称。
  final String? zoneName;

  /// 墙上时间是按本机时区换算得到的。
  final bool deviceZone;

  bool get hasTime => !dateOnly;

  /// 时区展示文案。
  String get zoneLabel {
    if (dateOnly) return '';
    if (deviceZone) return '本机${formatAgendaOffset(offset)}';
    final name = zoneName;
    if (name != null && name.isNotEmpty) return name;
    return formatAgendaOffset(offset);
  }
}

/// 时区偏移的展示文案。
String formatAgendaOffset(Duration? offset) {
  if (offset == null) return '';
  if (offset == Duration.zero) return 'UTC';
  final sign = offset.isNegative ? '-' : '+';
  final total = offset.abs();
  final hours = total.inHours.toString().padLeft(2, '0');
  final minutes = (total.inMinutes % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$minutes';
}

final _zones = _loadAgendaZones();

Map<String, tz.Location> _loadAgendaZones() {
  data.initializeTimeZones();
  return tz.timeZoneDatabase.locations;
}

/// 按目标日的 IANA 规则换算瞬间，覆盖夏令时和跨日偏移。
DateTime? agendaTimeInZone(DateTime instant, String? zoneName) {
  final zone = zoneName == 'UTC' ? tz.UTC : _zones[zoneName];
  return zone == null ? null : tz.TZDateTime.from(instant, zone);
}

final _dateOnlyPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _timestampPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?(Z|[+-]\d{2}:?\d{2})?$',
);

/// 解析服务端的时间取值。
///
/// [zoneName] 是服务端给出的 IANA 时区，用于把 UTC 取值换算回服务端本地时间。
AgendaMoment? parseAgendaMoment(String? value, {String? zoneName}) {
  if (value == null) return null;
  final text = value.trim();
  if (text.isEmpty) return null;
  final dateOnly = _dateOnlyPattern.firstMatch(text);
  if (dateOnly != null) {
    final wallClock = _wallClock(
      int.parse(dateOnly.group(1)!),
      int.parse(dateOnly.group(2)!),
      int.parse(dateOnly.group(3)!),
      0,
      0,
      0,
    );
    if (wallClock == null) return null;
    return AgendaMoment(
      wallClock: wallClock,
      dateOnly: true,
      zoneName: zoneName,
    );
  }
  final stamp = _timestampPattern.firstMatch(text);
  if (stamp == null) {
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return AgendaMoment(
      wallClock: DateTime.utc(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
      ),
      dateOnly: false,
      instant: parsed.toUtc(),
      offset: parsed.timeZoneOffset,
      deviceZone: true,
      zoneName: zoneName,
    );
  }
  final year = int.parse(stamp.group(1)!);
  final month = int.parse(stamp.group(2)!);
  final day = int.parse(stamp.group(3)!);
  final hour = int.parse(stamp.group(4)!);
  final minute = int.parse(stamp.group(5)!);
  final second = int.parse(stamp.group(6) ?? '0');
  final wallClock = _wallClock(year, month, day, hour, minute, second);
  if (wallClock == null) return null;
  final offset = _parseOffset(stamp.group(7));
  final instant = DateTime.tryParse(text)?.toUtc();
  if (instant == null) return null;
  final zoned = agendaTimeInZone(instant, zoneName);
  if (offset != null && offset != Duration.zero) {
    return AgendaMoment(
      wallClock: wallClock,
      dateOnly: false,
      instant: instant,
      offset: offset,
      zoneName: zoned?.timeZoneOffset == offset ? zoneName : null,
    );
  }
  if (zoned != null) {
    return AgendaMoment(
      wallClock: DateTime.utc(
        zoned.year,
        zoned.month,
        zoned.day,
        zoned.hour,
        zoned.minute,
        zoned.second,
      ),
      dateOnly: false,
      instant: instant,
      offset: zoned.timeZoneOffset,
      zoneName: zoneName,
    );
  }
  final local = instant.toLocal();
  return AgendaMoment(
    wallClock: local,
    dateOnly: false,
    instant: instant,
    offset: local.timeZoneOffset,
    deviceZone: true,
    zoneName: zoneName,
  );
}

DateTime? _wallClock(
  int year,
  int month,
  int day,
  int hour,
  int minute,
  int second,
) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour > 23 || minute > 59 || second > 59) return null;
  final moment = DateTime.utc(year, month, day, hour, minute, second);
  // DateTime 会把越界的日期滚动到下个月，这里按原始字段回查一次。
  if (moment.year != year || moment.month != month || moment.day != day) {
    return null;
  }
  return moment;
}

Duration? _parseOffset(String? text) {
  if (text == null || text.isEmpty) return null;
  if (text == 'Z') return Duration.zero;
  final sign = text.startsWith('-') ? -1 : 1;
  final digits = text.substring(1).replaceAll(':', '');
  if (digits.length != 4) return null;
  final hours = int.tryParse(digits.substring(0, 2));
  final minutes = int.tryParse(digits.substring(2, 4));
  if (hours == null || minutes == null) return null;
  return Duration(hours: hours, minutes: minutes) * sign;
}

/// 把日历日格式化成服务端使用的 `YYYY-MM-DD`。
String formatAgendaDate(DateTime day) {
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '${day.year.toString().padLeft(4, '0')}-$month-$date';
}

/// 把选中的时刻作为本地时刻交给服务端按指定时区校验。
String formatAgendaLocalTimestamp(DateTime day, TimeOfDay time) =>
    '${formatAgendaDate(day)}T${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// 时间的展示文案。带时刻时同时给出时区，避免和本机时区混淆。
String formatAgendaMoment(BuildContext context, AgendaMoment moment) {
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatMediumDate(moment.wallClock);
  if (moment.dateOnly) return date;
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(moment.wallClock),
    alwaysUse24HourFormat: true,
  );
  final zone = moment.zoneLabel;
  return zone.isEmpty ? '$date $time' : '$date $time（$zone）';
}
