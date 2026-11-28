import 'package:pi_muse_flutter/src/network/api.dart';

/// 审批预览中的单条条目。
typedef ProposalItem = ({String label, String value});

/// 需要用户逐次确认的写操作审批。
class Approval {
  const Approval({
    required this.id,
    required this.sessionId,
    required this.runId,
    required this.revision,
    required this.kind,
    required this.status,
    required this.title,
    required this.execution,
    required this.previewType,
    required this.scope,
    required this.path,
    required this.before,
    required this.after,
    required this.beforeExists,
    required this.category,
    required this.summary,
    required this.target,
    required this.items,
    required this.confirmLabel,
    required this.denyLabel,
    required this.expiresAt,
  });

  factory Approval.fromJson(Json json) {
    final preview = json['preview'] as Json;
    final previewType = preview['type'] as String? ?? 'file_diff';
    final rawItems = preview['items'] as List? ?? const [];
    final items = <ProposalItem>[
      for (final item in rawItems)
        if (item is Json && item['label'] is String && item['value'] is String)
          (label: item['label'] as String, value: item['value'] as String),
    ];
    return Approval(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String?,
      runId: json['runId'] as String?,
      revision: json['revision'] as int,
      kind:
          json['kind'] as String? ??
          (previewType == 'proposal' ? 'proposal' : 'file_write'),
      status: json['status'] as String,
      title: json['title'] as String?,
      execution: json['execution'] as Json?,
      previewType: previewType,
      scope: preview['scope'] as String? ?? 'workspace',
      path: preview['path'] as String? ?? '',
      before: preview['before'] as String? ?? '',
      after: preview['after'] as String? ?? '',
      beforeExists: preview['beforeExists'] as bool? ?? false,
      category: preview['category'] as String? ?? 'general',
      summary: preview['summary'] as String? ?? '',
      target: preview['target'] as String?,
      items: List.unmodifiable(items),
      confirmLabel: preview['confirmLabel'] as String?,
      denyLabel: preview['denyLabel'] as String?,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }

  final String id;
  final String? sessionId;
  final String? runId;
  final int revision;
  final String kind;
  final String status;
  final String? title;
  final Json? execution;
  final String previewType;
  final String scope;
  final String path;
  final String before;
  final String after;
  final bool beforeExists;
  final String category;
  final String summary;
  final String? target;
  final List<ProposalItem> items;
  final String? confirmLabel;
  final String? denyLabel;
  final DateTime expiresAt;

  bool get isFileDiff => previewType == 'file_diff';
  bool get isProposal => previewType == 'proposal';

  String get displayTitle {
    final trimmed = title?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return isFileDiff ? path : summary;
  }

  String? get targetLabel {
    if (isFileDiff) return path.isNotEmpty ? path : null;
    return target?.isNotEmpty == true ? target : null;
  }

  String get scopeOrCategoryLabel {
    if (isFileDiff) {
      return switch (scope) {
        'skill' => '技能文件',
        'profile' => '个人设定',
        'memory' => '长期记忆',
        'custom' => '自定义目标',
        _ => '工作区文件',
      };
    }
    return switch (category) {
      'habit_learning' => '习惯学习',
      'profile' => '个人设定',
      _ => kind == 'action' ? '操作确认' : '建议确认',
    };
  }

  String get approveButtonLabel {
    final custom = confirmLabel?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return isFileDiff ? '批准修改' : '批准';
  }

  String get denyButtonLabel {
    final custom = denyLabel?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return '拒绝';
  }

  Approval copyWithResolution({
    required int revision,
    required String status,
    required Json? execution,
  }) => Approval(
    id: id,
    sessionId: sessionId,
    runId: runId,
    revision: revision,
    kind: kind,
    status: status,
    title: title,
    execution: execution ?? this.execution,
    previewType: previewType,
    scope: scope,
    path: path,
    before: before,
    after: after,
    beforeExists: beforeExists,
    category: category,
    summary: summary,
    target: target,
    items: items,
    confirmLabel: confirmLabel,
    denyLabel: denyLabel,
    expiresAt: expiresAt,
  );
}
