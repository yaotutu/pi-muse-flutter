import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'chat.dart';

class ExecutionDetailsPage extends StatefulWidget {
  const ExecutionDetailsPage({
    super.key,
    required this.chat,
    required this.sessionId,
    required this.title,
    required this.openApproval,
  });

  final ChatController chat;
  final String sessionId;
  final String title;
  final void Function(BuildContext, String, Approval?) openApproval;

  @override
  State<ExecutionDetailsPage> createState() => _ExecutionDetailsPageState();
}

class _ExecutionDetailsPageState extends State<ExecutionDetailsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _visited = {0};
  bool _approvalHistory = false;
  String _approvalStatus = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (_visited.add(_tabs.index)) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openApprovalById(String id) =>
      widget.openApproval(context, id, widget.chat.approvals[id]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('执行详情'),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: '执行记录'),
          Tab(text: '审批'),
        ],
      ),
    ),
    body: SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _RunHistoryTab(
                  chat: widget.chat,
                  sessionId: widget.sessionId,
                  onOpenPendingTab: () => _tabs.animateTo(1),
                  onOpenApproval: _openApprovalById,
                ),
                if (_visited.contains(1))
                  _buildApprovals()
                else
                  const SizedBox(),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildApprovals() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (_approvalHistory)
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _approvalStatus,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部结果')),
                    for (final status in [
                      'approved',
                      'denied',
                      'expired',
                      'cancelled',
                    ])
                      DropdownMenuItem(
                        value: status,
                        child: Text(executionStatus(status)),
                      ),
                  ],
                  onChanged: (status) =>
                      setState(() => _approvalStatus = status ?? ''),
                ),
              )
            else
              const Spacer(),
            TextButton(
              onPressed: () =>
                  setState(() => _approvalHistory = !_approvalHistory),
              child: Text(_approvalHistory ? '待审批' : '查看审批历史'),
            ),
          ],
        ),
      ),
      Expanded(
        child: _approvalHistory
            ? _ApprovalHistoryList(
                key: ValueKey(_approvalStatus),
                chat: widget.chat,
                sessionId: widget.sessionId,
                approvalStatus: _approvalStatus,
                onOpen: (id) => widget.openApproval(context, id, null),
              )
            : ListenableBuilder(
                listenable: widget.chat,
                builder: (context, _) {
                  if (!widget.chat.synchronized) {
                    return const Center(child: Text('审批状态待同步'));
                  }
                  final items = widget.chat.sessionApprovals(widget.sessionId);
                  if (items.isEmpty) {
                    return const Center(child: Text('当前没有待审批的请求'));
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final target = item.targetLabel;
                      return ListTile(
                        leading: Icon(
                          item.isProposal
                              ? Icons.fact_check_outlined
                              : Icons.description_outlined,
                        ),
                        title: Text(item.displayTitle),
                        subtitle: target != null && target != item.displayTitle
                            ? Text(target)
                            : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            widget.openApproval(context, item.id, item),
                      );
                    },
                  );
                },
              ),
      ),
    ],
  );
}

class _RunHistoryTab extends StatefulWidget {
  const _RunHistoryTab({
    required this.chat,
    required this.sessionId,
    required this.onOpenPendingTab,
    required this.onOpenApproval,
  });

  final ChatController chat;
  final String sessionId;
  final VoidCallback onOpenPendingTab;
  final ValueChanged<String> onOpenApproval;

  @override
  State<_RunHistoryTab> createState() => _RunHistoryTabState();
}

class _RunHistoryTabState extends State<_RunHistoryTab>
    with AutomaticKeepAliveClientMixin {
  final _fetched = <String, Json>{};
  (int, int)? _version;
  bool _loading = false;
  bool _failed = false;
  bool _loaded = false;
  String? _cursor;
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
    final chat = widget.chat;
    if (!chat.synchronized) {
      if (_version != null) {
        _request++;
        setState(() {
          _version = null;
          _loading = false;
        });
      }
      return;
    }
    final version = chat.executionHistoryVersion(
      widget.sessionId,
      approvals: false,
    );
    if (_version == version) return;
    _version = version;
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    final cursor = more ? _cursor : null;
    if (!widget.chat.synchronized || (more && (_loading || cursor == null))) {
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final data = await widget.chat.readExecution(
        '/api/runs',
        query: {
          'sessionId': widget.sessionId,
          'limit': '20',
          'cursor': ?cursor,
        },
      );
      if (!mounted || request != _request) return;
      final rows = (data['runs'] as List? ?? const []).cast<Json>();
      final next = data['nextCursor'] as String?;
      setState(() {
        if (!more) _fetched.clear();
        for (final row in rows) {
          final runId = row['runId'];
          if (runId is String && runId.isNotEmpty) {
            _fetched[runId] = row;
          }
        }
        _cursor = next;
        _loaded = true;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  List<Json> _mergedRuns() {
    final byId = <String, Json>{..._fetched};
    for (final run in widget.chat.executionRuns(widget.sessionId)) {
      final runId = run['runId'];
      if (runId is String && runId.isNotEmpty) {
        byId[runId] = run;
      }
    }
    final items = byId.values.where(_isMeaningfulRun).toList();
    items.sort((a, b) {
      final aRunning = a['status'] == 'running' ? 0 : 1;
      final bRunning = b['status'] == 'running' ? 0 : 1;
      if (aRunning != bRunning) return aRunning.compareTo(bRunning);
      final aTime = a['startedAt'] as String? ?? '';
      final bTime = b['startedAt'] as String? ?? '';
      return bTime.compareTo(aTime);
    });
    return items;
  }

  bool _isMeaningfulRun(Json run) {
    final steps = widget.chat.stepsOf(run);
    final tools = (run['tools'] as List? ?? const []);
    final subagents = (run['subagents'] as List? ?? const []);
    final noActions = steps.isEmpty && tools.isEmpty && subagents.isEmpty;
    if (run['title'] == '正在处理请求' && noActions) return false;
    final status = run['status'] as String?;
    if (status == 'running' || run['source'] == 'job') return true;
    if (!noActions) return true;
    return status == 'failed' || status == 'cancelled';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: widget.chat,
      builder: (context, _) {
        if (!widget.chat.synchronized) {
          return const Center(child: Text('执行状态待同步'));
        }
        final pending = widget.chat.sessionApprovals(widget.sessionId);
        final runs = _mergedRuns();
        final timeline = _buildTimelineEntries(runs);
        final groups = _groupEntriesByDay(timeline);
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (pending.isNotEmpty) ...[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text('等待你的审批（${pending.length} 项）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenPendingTab,
                ),
                const Divider(height: 1),
              ],
              if (_loading) const LinearProgressIndicator(),
              if (_failed && timeline.isEmpty)
                TextButton(
                  onPressed: _load,
                  child: const Text('读取失败，点此重试'),
                )
              else if (_loaded && timeline.isEmpty && !_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
                  child: Column(
                    children: [
                      Icon(
                        Icons.checklist_rtl_outlined,
                        size: 36,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '暂无执行记录',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '仅记录调用工具、子代理、审批、定时任务或异常中断的操作；普通纯文字问答不记入此处。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final group in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                  child: Text(
                    group.dayLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (var i = 0; i < group.entries.length; i++)
                  _TimelineItemRow(
                    entry: group.entries[i],
                    isFirst: i == 0,
                    isLast: i == group.entries.length - 1,
                    onOpenApproval: widget.onOpenApproval,
                  ),
              ],
              if (_failed && timeline.isNotEmpty)
                TextButton(
                  onPressed: _load,
                  child: const Text('加载失败，点此重试'),
                ),
              if (_cursor != null && !_failed)
                TextButton(
                  onPressed: _loading || !widget.chat.synchronized
                      ? null
                      : () => _load(more: true),
                  child: const Text('加载更多'),
                ),
            ],
          ),
        );
      },
    );
  }

  List<_TimelineEntry> _buildTimelineEntries(List<Json> runs) {
    final entries = <_TimelineEntry>[];
    for (final run in runs) {
      final runStartedAt = _displayText(run['startedAt']);
      final runEndedAt = _displayText(run['endedAt']);
      final steps = widget.chat.stepsOf(run);
      final tools = (run['tools'] as List? ?? const []).cast<Json>();
      final subagents = (run['subagents'] as List? ?? const []).cast<Json>();
      if (steps.isNotEmpty) {
        final merged = <_TimelineEntry>[];
        for (final step in steps) {
          final kind = _displayText(step['kind']) ?? 'tool';
          final toolName = _displayText(step['toolName']);
          final title = _displayText(step['title']) ?? '执行步骤';
          final detail = _displayText(step['detail']);
          final status = _displayText(step['status']) ?? 'succeeded';
          final result = _displayText(step['result']);
          final approvalId = _displayText(step['approvalId']);
          final timestamp =
              _displayText(step['endedAt']) ??
              _displayText(step['startedAt']) ??
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
              detail: _displayText(agent['role']),
              status: _displayText(agent['status']) ?? 'succeeded',
              result: _displayText(agent['label']),
              timestamp:
                  _displayText(agent['endedAt']) ??
                  _displayText(agent['startedAt']) ??
                  runStartedAt,
            ),
          );
        }
        for (final tool in tools.reversed) {
          entries.add(
            _TimelineEntry(
              kind: 'tool',
              title: _displayText(tool['label']) ?? '工具',
              status: _displayText(tool['status']) ?? 'running',
              timestamp: runStartedAt,
            ),
          );
        }
        continue;
      }
      final rawTitle = _displayText(run['title']);
      final title = (rawTitle != null && rawTitle != '正在处理请求')
          ? rawTitle
          : (run['source'] == 'job' ? '定时任务' : '执行记录');
      entries.add(
        _TimelineEntry(
          kind: run['source'] == 'job' ? 'job' : 'run',
          title: title,
          status: _displayText(run['status']) ?? 'failed',
          result: _displayText(run['label']),
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
}

class _ApprovalHistoryList extends StatefulWidget {
  const _ApprovalHistoryList({
    super.key,
    required this.chat,
    required this.sessionId,
    required this.onOpen,
    required this.approvalStatus,
  });

  final ChatController chat;
  final String sessionId;
  final ValueChanged<String> onOpen;
  final String approvalStatus;

  @override
  State<_ApprovalHistoryList> createState() => _ApprovalHistoryListState();
}

class _ApprovalHistoryListState extends State<_ApprovalHistoryList>
    with AutomaticKeepAliveClientMixin {
  final _items = <String, Json>{};
  (int, int)? _version;
  bool _loading = false;
  bool _failed = false;
  bool _loaded = false;
  String? _cursor;
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
    final chat = widget.chat;
    if (!chat.synchronized) {
      if (_version != null) {
        _request++;
        setState(() {
          _version = null;
          _loading = false;
        });
      }
      return;
    }
    final version = chat.executionHistoryVersion(
      widget.sessionId,
      approvals: true,
    );
    if (_version == version) return;
    _version = version;
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    final cursor = more ? _cursor : null;
    if (!widget.chat.synchronized || (more && (_loading || cursor == null))) {
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final data = await widget.chat.readExecution(
        '/api/approvals',
        query: {
          'sessionId': widget.sessionId,
          'cursor': ?cursor,
          if (widget.approvalStatus.isNotEmpty) 'status': widget.approvalStatus,
        },
      );
      if (!mounted || request != _request) return;
      final rows = (data['approvals'] as List).cast<Json>();
      final items = {
        for (final row in rows)
          if (row['sessionId'] == widget.sessionId) row['id'] as String: row,
      };
      final next = data['nextCursor'] as String?;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(items);
        _cursor = next;
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (!widget.chat.synchronized) const ListTile(title: Text('状态待同步')),
          for (final row in _items.values)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(row['title'] as String),
              subtitle: Text(executionStatus(row['status'])),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => widget.onOpen(row['id'] as String),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_failed)
            TextButton(onPressed: _load, child: const Text('读取失败，点此重试'))
          else if (_loaded && _items.isEmpty && !_loading)
            const ListTile(title: Text('暂无已处理的审批')),
          if (_cursor != null && !_failed)
            TextButton(
              onPressed: _loading || !widget.chat.synchronized
                  ? null
                  : () => _load(more: true),
              child: const Text('加载更多'),
            ),
        ],
      ),
    );
  }
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
  });

  final String kind;
  final String? toolName;
  final String title;
  final String? detail;
  final String status;
  final String? result;
  final String? approvalId;
  final String? timestamp;

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
  );
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

String? _displayText(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

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

String executionStatus(Object? status) => switch (status) {
  'queued' => '排队中',
  'running' => '进行中',
  'waiting_approval' => '等待审批',
  'waiting_user' => '等待用户补充',
  'awaiting_continuation' => '等待继续',
  'succeeded' || 'completed' => '已完成',
  'failed' => '失败',
  'stopped' => '已停止',
  'cancelled' => '已取消',
  'interrupted' => '已中断',
  'pending' => '待审批',
  'approved' => '已批准',
  'denied' => '已拒绝',
  'expired' => '已过期',
  _ => '状态未知',
};
