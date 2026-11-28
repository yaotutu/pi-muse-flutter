import 'package:pi_muse_flutter/src/network/api.dart';

/// 主会话标识。客户端固定用它承载默认聊天。
const mainSession = 'main';

/// 会话目录中的一个条目。
class SessionEntry {
  const SessionEntry(this.id, this.title);

  factory SessionEntry.fromJson(Json json) =>
      SessionEntry(json['id'] as String, json['title'] as String);

  final String id;
  final String title;
}

/// 删除会话时附属计划任务的处理方式。
enum SessionScheduleDisposition {
  delete('delete'),
  moveToMain('move-to-main');

  const SessionScheduleDisposition(this.value);
  final String value;
}

/// 会话附属的计划任务与监控快照。
class SessionSchedules {
  SessionSchedules.fromJson(Json json)
    : revision = json['scheduleRevision'] as String,
      jobs = _titles(json['jobs']),
      monitors = _titles(json['monitors']) {
    if (!_validRevision.hasMatch(revision)) throw const FormatException();
  }

  static final _validRevision = RegExp(r'^[a-f0-9]{64}$');
  static List<String> _titles(Object? items) => List.unmodifiable(
    (items as List).cast<Json>().map((entry) => entry['title'] as String),
  );

  final String revision;
  final List<String> jobs;
  final List<String> monitors;

  bool get isEmpty => jobs.isEmpty && monitors.isEmpty;
}

/// 会话变更的核对结果。
enum SessionChangeResult { confirmed, differentTitle, unknown }
