import 'dart:async';
import 'package:material_ui/material_ui.dart';

import '../../../network/api.dart';
import '../chat_controller.dart';
import 'execution_display.dart';

class SessionSchedulesTab extends StatefulWidget {
  const SessionSchedulesTab({
    super.key,
    required this.chat,
    required this.sessionId,
  });

  final ChatController chat;
  final String sessionId;

  @override
  State<SessionSchedulesTab> createState() => SessionSchedulesTabState();
}

class SessionSchedulesTabState extends State<SessionSchedulesTab>
    with AutomaticKeepAliveClientMixin {
  List<Json> _jobs = const [];
  List<Json> _monitors = const [];
  bool _loading = false;
  bool _failed = false;
  bool _loaded = false;
  bool _wasSynced = false;
  int _request = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_onChange);
    _onChange();
  }

  @override
  void dispose() {
    widget.chat.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!widget.chat.synchronized) {
      if (_wasSynced) {
        _request++;
        setState(() {
          _wasSynced = false;
          _loading = false;
        });
      }
      return;
    }
    if (_wasSynced) return;
    _wasSynced = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!widget.chat.synchronized) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait([
        widget.chat.readExecution(
          '/api/jobs',
          query: {'sessionId': widget.sessionId},
        ),
        widget.chat.readExecution(
          '/api/monitors',
          query: {'sessionId': widget.sessionId},
        ),
      ]);
      if (!mounted || request != _request) return;
      setState(() {
        _jobs = (results[0]['jobs'] as List? ?? const []).cast<Json>();
        _monitors = (results[1]['monitors'] as List? ?? const []).cast<Json>();
        _loaded = true;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: widget.chat,
      builder: (context, _) {
        if (!widget.chat.synchronized) {
          return const Center(child: Text('会话状态待同步'));
        }
        final hasItems = _jobs.isNotEmpty || _monitors.isNotEmpty;
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_failed && !hasItems)
                TextButton(onPressed: _load, child: const Text('读取失败，点此重试'))
              else if (_loaded && !hasItems && !_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 36,
                    horizontal: 12,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.schedule_outlined,
                        size: 36,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '暂无定时任务',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '在聊天中让助手设置的定时提醒、周期任务或网页监控都会归集在这里。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_jobs.isNotEmpty) ...[
                if (_monitors.isNotEmpty)
                  const _ScheduleSectionHeader(title: '定时任务'),
                for (final job in _jobs) _buildJobCard(job),
              ],
              if (_monitors.isNotEmpty) ...[
                const _ScheduleSectionHeader(title: '网页监控'),
                for (final monitor in _monitors) _buildMonitorCard(monitor),
              ],
              if (_failed && hasItems)
                TextButton(onPressed: _load, child: const Text('刷新失败，点此重试')),
            ],
          ),
        );
      },
    );
  }

  Widget _buildJobCard(Json job) {
    final title =
        executionText(job['title']) ?? executionText(job['prompt']) ?? '定时任务';
    final status = executionText(job['status']);
    final at = executionText(job['at']);
    final daily = job['daily'] == true;
    final nextRunAt = _formatScheduleTime(job['nextRunAt']);
    final scheduleParts = <String>[
      if (at != null) daily ? '每天 $at' : '单次 ${_formatScheduleTime(at) ?? at}',
      if ((status == 'scheduled' || status == 'queued') && nextRunAt != null)
        '下次 $nextRunAt',
    ];
    final error = executionText(job['error']);
    final lastResult = executionText(job['lastResult']);
    return _ScheduleItemCard(
      icon: Icons.schedule_outlined,
      title: title,
      status: status,
      subtitle: scheduleParts.isEmpty ? null : scheduleParts.join(' · '),
      detail: error ?? lastResult,
      detailIsError: error != null,
    );
  }

  Widget _buildMonitorCard(Json monitor) {
    final title =
        executionText(monitor['title']) ??
        executionText(monitor['url']) ??
        '网页监控';
    final status = executionText(monitor['status']);
    final condition = executionText(monitor['condition']);
    final value = executionText(monitor['value']);
    final interval = monitor['intervalMinutes'];
    final lastChecked = _formatScheduleTime(monitor['lastCheckedAt']);
    final parts = <String>[
      condition == 'contains' && value != null ? '包含关键词「$value」' : '页面变化时通知',
      if (interval is num) '每 ${interval.toInt()} 分钟',
      if (lastChecked != null) '上次检查 $lastChecked',
    ];
    final error = executionText(monitor['error']);
    return _ScheduleItemCard(
      icon: Icons.travel_explore_outlined,
      title: title,
      status: status,
      subtitle: parts.join(' · '),
      detail: error ?? executionText(monitor['url']),
      detailIsError: error != null,
    );
  }
}

class _ScheduleSectionHeader extends StatelessWidget {
  const _ScheduleSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ScheduleItemCard extends StatelessWidget {
  const _ScheduleItemCard({
    required this.icon,
    required this.title,
    required this.status,
    this.subtitle,
    this.detail,
    this.detailIsError = false,
  });

  final IconData icon;
  final String title;
  final String? status;
  final String? subtitle;
  final String? detail;
  final bool detailIsError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusLabel = _scheduleStatusLabel(status);
    final badgeBg = switch (status) {
      'running' ||
      'active' ||
      'scheduled' ||
      'queued' => colors.primaryContainer,
      'failed' => colors.errorContainer,
      _ => colors.surfaceContainerHighest,
    };
    final badgeFg = switch (status) {
      'running' ||
      'active' ||
      'scheduled' ||
      'queued' => colors.onPrimaryContainer,
      'failed' => colors.onErrorContainer,
      _ => colors.onSurfaceVariant,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: colors.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: badgeFg,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: detailIsError
                          ? colors.error
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _scheduleStatusLabel(Object? status) => switch (status) {
  'scheduled' => '已排期',
  'running' => '执行中',
  'paused' => '已暂停',
  'succeeded' => '已完成',
  'failed' => '失败',
  'cancelled' => '已取消',
  'queued' => '排队中',
  'active' => '监控中',
  'stopped' => '已停止',
  _ => executionStatus(status),
};

String? _formatScheduleTime(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return raw;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(parsed.month)}-${two(parsed.day)} '
      '${two(parsed.hour)}:${two(parsed.minute)}';
}
