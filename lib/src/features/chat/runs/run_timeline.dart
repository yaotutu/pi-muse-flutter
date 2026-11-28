import 'package:material_ui/material_ui.dart';

import '../../../network/api.dart';
import 'execution_display.dart';

List<Widget> buildRunTimeline(
  BuildContext context,
  List<Json> runs, {
  required List<Json> Function(Json run) stepsOf,
  required ValueChanged<String> onOpenApproval,
}) {
  final groups = _groupEntriesByDay(_buildTimelineEntries(runs, stepsOf));
  final theme = Theme.of(context);
  return [
    for (final group in groups) ...[
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(
          group.dayLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      ..._buildDayTimelineWidgets(
        group.entries,
        onOpenApproval: onOpenApproval,
      ),
    ],
  ];
}

List<Widget> _buildDayTimelineWidgets(
  List<_TimelineEntry> entries, {
  required ValueChanged<String> onOpenApproval,
}) {
  final rows = <_TimelineDayRow>[];
  String? prevTaskKey;
  for (final entry in entries) {
    final taskTitle = entry.taskTitle;
    final taskKey = taskTitle != null ? (entry.runId ?? taskTitle) : null;
    if (taskTitle != null && taskKey != prevTaskKey) {
      rows.add(
        _TimelineTaskRow(taskTitle: taskTitle, taskSource: entry.taskSource),
      );
    }
    prevTaskKey = taskKey;
    rows.add(_TimelineStepRow(entry: entry));
  }
  return [
    for (var i = 0; i < rows.length; i++)
      switch (rows[i]) {
        _TimelineTaskRow(:final taskTitle, :final taskSource) =>
          _TimelineTaskMarkerRow(
            taskTitle: taskTitle,
            taskSource: taskSource,
            isFirst: i == 0,
            isLast: i == rows.length - 1,
          ),
        _TimelineStepRow(:final entry) => _TimelineItemRow(
          entry: entry,
          isFirst: i == 0,
          isLast: i == rows.length - 1,
          onOpenApproval: onOpenApproval,
        ),
      },
  ];
}

List<_TimelineEntry> _buildTimelineEntries(
  List<Json> runs,
  List<Json> Function(Json run) stepsOf,
) {
  final entries = <_TimelineEntry>[];
  for (final run in runs) {
    final runId = executionText(run['runId']);
    final taskSource = executionText(run['source']);
    final taskTitle = _runTaskTitle(run);
    final runStartedAt = executionText(run['startedAt']);
    final runEndedAt = executionText(run['endedAt']);
    final steps = stepsOf(run);
    final tools = (run['tools'] as List? ?? const []).cast<Json>();
    final subagents = (run['subagents'] as List? ?? const []).cast<Json>();
    if (steps.isNotEmpty) {
      final merged = <_TimelineEntry>[];
      for (final step in steps) {
        final kind = executionText(step['kind']) ?? 'tool';
        final toolName = executionText(step['toolName']);
        final title = executionText(step['title']) ?? '执行步骤';
        final detail = executionText(step['detail']);
        final status = executionText(step['status']) ?? 'succeeded';
        final result = executionText(step['result']);
        final approvalId = executionText(step['approvalId']);
        final timestamp =
            executionText(step['endedAt']) ??
            executionText(step['startedAt']) ??
            runStartedAt;
        if (kind == 'file_commit' && merged.isNotEmpty) {
          final prev = merged.last;
          final matchesPrevFileTool =
              prev.kind == 'tool' &&
              (prev.toolName == 'write' ||
                  prev.toolName == 'edit' ||
                  prev.title == '写入文件' ||
                  prev.title == '编辑文件') &&
              prev.detail == detail;
          if (matchesPrevFileTool) {
            merged[merged.length - 1] = prev.copyWith(
              status: status,
              result: result ?? prev.result,
              approvalId: prev.approvalId ?? approvalId,
              timestamp: timestamp ?? prev.timestamp,
            );
            continue;
          }
        }
        merged.add(
          _TimelineEntry(
            kind: kind,
            toolName: toolName,
            title: title,
            detail: detail,
            status: status,
            result: result,
            approvalId: approvalId,
            timestamp: timestamp,
            runId: runId,
            taskTitle: taskTitle,
            taskSource: taskSource,
          ),
        );
      }
      entries.addAll(merged.reversed);
      continue;
    }
    if (tools.isNotEmpty || subagents.isNotEmpty) {
      for (final agent in subagents.reversed) {
        entries.add(
          _TimelineEntry(
            kind: 'subagent',
            title: '委派子代理',
            detail: executionText(agent['role']),
            status: executionText(agent['status']) ?? 'succeeded',
            result: executionText(agent['label']),
            timestamp:
                executionText(agent['endedAt']) ??
                executionText(agent['startedAt']) ??
                runStartedAt,
            runId: runId,
            taskTitle: taskTitle,
            taskSource: taskSource,
          ),
        );
      }
      for (final tool in tools.reversed) {
        entries.add(
          _TimelineEntry(
            kind: 'tool',
            title: executionText(tool['label']) ?? '工具',
            status: executionText(tool['status']) ?? 'running',
            timestamp: runStartedAt,
            runId: runId,
            taskTitle: taskTitle,
            taskSource: taskSource,
          ),
        );
      }
      continue;
    }
    final title = taskTitle ?? (taskSource == 'job' ? '定时任务' : '执行记录');
    entries.add(
      _TimelineEntry(
        kind: taskSource == 'job' ? 'job' : 'run',
        title: title,
        status: executionText(run['status']) ?? 'failed',
        result: executionText(run['label']),
        timestamp: runEndedAt ?? runStartedAt,
      ),
    );
  }
  return entries;
}

List<({String dayLabel, List<_TimelineEntry> entries})> _groupEntriesByDay(
  List<_TimelineEntry> entries,
) {
  final groups = <({String dayLabel, List<_TimelineEntry> entries})>[];
  for (final entry in entries) {
    final label = _timelineDayLabel(entry.timestamp);
    if (groups.isEmpty || groups.last.dayLabel != label) {
      groups.add((dayLabel: label, entries: [entry]));
    } else {
      groups.last.entries.add(entry);
    }
  }
  return groups;
}

sealed class _TimelineDayRow {
  const _TimelineDayRow();
}

final class _TimelineTaskRow extends _TimelineDayRow {
  const _TimelineTaskRow({required this.taskTitle, this.taskSource});

  final String taskTitle;
  final String? taskSource;
}

final class _TimelineStepRow extends _TimelineDayRow {
  const _TimelineStepRow({required this.entry});

  final _TimelineEntry entry;
}

class _TimelineEntry {
  const _TimelineEntry({
    required this.kind,
    required this.title,
    required this.status,
    this.toolName,
    this.detail,
    this.result,
    this.approvalId,
    this.timestamp,
    this.runId,
    this.taskTitle,
    this.taskSource,
  });

  final String kind;
  final String? toolName;
  final String title;
  final String? detail;
  final String status;
  final String? result;
  final String? approvalId;
  final String? timestamp;
  final String? runId;
  final String? taskTitle;
  final String? taskSource;

  _TimelineEntry copyWith({
    String? status,
    String? result,
    String? approvalId,
    String? timestamp,
  }) => _TimelineEntry(
    kind: kind,
    toolName: toolName,
    title: title,
    detail: detail,
    status: status ?? this.status,
    result: result ?? this.result,
    approvalId: approvalId ?? this.approvalId,
    timestamp: timestamp ?? this.timestamp,
    runId: runId,
    taskTitle: taskTitle,
    taskSource: taskSource,
  );
}

class _TimelineTaskMarkerRow extends StatelessWidget {
  const _TimelineTaskMarkerRow({
    required this.taskTitle,
    this.taskSource,
    required this.isFirst,
    required this.isLast,
  });

  final String taskTitle;
  final String? taskSource;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = taskSource == 'job'
        ? (taskTitle == '定时任务' ? '定时任务' : '定时任务 · $taskTitle')
        : '任务 · $taskTitle';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 1.5,
                  height: isFirst ? 10 : 14,
                  color: isFirst ? Colors.transparent : colors.outlineVariant,
                ),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary.withValues(alpha: 0.45),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: isLast ? Colors.transparent : colors.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(4, isFirst ? 0 : 6, 4, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.7,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        taskSource == 'job'
                            ? Icons.schedule_outlined
                            : Icons.chat_bubble_outline_rounded,
                        size: 13,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineItemRow extends StatelessWidget {
  const _TimelineItemRow({
    required this.entry,
    required this.isFirst,
    required this.isLast,
    required this.onOpenApproval,
  });

  final _TimelineEntry entry;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<String> onOpenApproval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dotColor = switch (entry.status) {
      'running' || 'waiting_approval' => colors.primary,
      'failed' || 'denied' || 'expired' => colors.error,
      'succeeded' || 'completed' => colors.tertiary,
      _ => colors.onSurfaceVariant,
    };
    final activeDot =
        entry.status == 'running' || entry.status == 'waiting_approval';
    final statusText = executionStatus(entry.status);
    final subtitle = entry.result != null && entry.result != statusText
        ? '$statusText · ${entry.result}'
        : statusText;
    final timeText = _timelineClock(entry.timestamp);
    final titleText = entry.detail != null
        ? '${entry.title} · ${entry.detail}'
        : entry.title;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(4, 2, 4, isLast ? 6 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  titleText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (timeText != null || entry.approvalId != null) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (timeText != null)
                      Text(
                        timeText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    if (entry.approvalId != null)
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  entry.status == 'failed' ||
                      entry.status == 'denied' ||
                      entry.status == 'expired'
                  ? colors.error
                  : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 1.5,
                  height: 6,
                  color: isFirst ? Colors.transparent : colors.outlineVariant,
                ),
                Container(
                  width: activeDot ? 11 : 9,
                  height: activeDot ? 11 : 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeDot ? colors.surface : dotColor,
                    border: activeDot
                        ? Border.all(color: dotColor, width: 2.5)
                        : null,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: isLast ? Colors.transparent : colors.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: entry.approvalId != null
                ? InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onOpenApproval(entry.approvalId!),
                    child: content,
                  )
                : content,
          ),
        ],
      ),
    );
  }
}

String? _runTaskTitle(Json run) {
  final raw = executionText(run['title'])?.trim();
  if (raw != null && raw.isNotEmpty && raw != '正在处理请求') return raw;
  if (run['source'] == 'job') return '定时任务';
  return null;
}

String _timelineDayLabel(Object? raw) {
  if (raw is! String || raw.isEmpty) return '较早记录';
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return '较早记录';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(parsed.year, parsed.month, parsed.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (parsed.year == now.year) return '${parsed.month}月${parsed.day}日';
  return '${parsed.year}年${parsed.month}月${parsed.day}日';
}

String? _timelineClock(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return null;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(parsed.hour)}:${two(parsed.minute)}';
}
