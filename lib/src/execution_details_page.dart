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
  final _expanded = <String>{};
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
    final items = byId.values.toList();
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
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (pending.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text('等待你的审批（${pending.length} 项）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenPendingTab,
                ),
              if (_loading) const LinearProgressIndicator(),
              if (_failed && runs.isEmpty)
                TextButton(
                  onPressed: _load,
                  child: const Text('读取失败，点此重试'),
                )
              else if (_loaded && runs.isEmpty && !_loading)
                const ListTile(title: Text('暂无执行记录')),
              for (final run in runs) _buildRunCard(context, run),
              if (_failed && runs.isNotEmpty)
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

  Widget _buildRunCard(BuildContext context, Json run) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final runId = run['runId'] as String? ?? '';
    final steps = widget.chat.stepsOf(run);
    final tools = (run['tools'] as List? ?? const []).cast<Json>();
    final subagents = (run['subagents'] as List? ?? const []).cast<Json>();
    final hasDetails =
        steps.isNotEmpty || tools.isNotEmpty || subagents.isNotEmpty;
    final isRunning = run['status'] == 'running';
    final expanded = isRunning || _expanded.contains(runId);
    final title =
        _displayText(run['title']) ??
        (run['source'] == 'job' ? '定时任务' : '聊天执行');
    final statusLabel =
        _displayText(run['label']) ?? executionStatus(run['status']);
    final summary = steps.isNotEmpty
        ? '$statusLabel · ${steps.length} 步'
        : statusLabel;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: hasDetails && !isRunning
                  ? () => setState(() {
                      if (!_expanded.remove(runId)) _expanded.add(runId);
                    })
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasDetails && !isRunning)
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: colors.onSurfaceVariant,
                    ),
                ],
              ),
            ),
            if (expanded && steps.isNotEmpty) ...[
              const SizedBox(height: 8),
              RunStepsList(
                steps: steps,
                onOpenApproval: widget.onOpenApproval,
              ),
            ] else if (expanded) ...[
              for (final tool in tools)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.build_outlined),
                  title: Text(_displayText(tool['label']) ?? '工具'),
                  subtitle: Text(executionStatus(tool['status'])),
                ),
              for (final agent in subagents)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(_displayText(agent['role']) ?? '子任务'),
                  subtitle: Text(
                    _displayText(agent['label']) ??
                        executionStatus(agent['status']),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
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

class RunStepsList extends StatelessWidget {
  const RunStepsList({
    super.key,
    required this.steps,
    this.compact = false,
    this.onOpenApproval,
  });

  final List<Json> steps;
  final bool compact;
  final ValueChanged<String>? onOpenApproval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          _buildStep(context, theme, colors, steps[i], i == steps.length - 1),
      ],
    );
  }

  Widget _buildStep(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    Json step,
    bool isLast,
  ) {
    final kind = step['kind'] as String? ?? 'tool';
    final status = step['status'] as String?;
    final title = _displayText(step['title']) ?? '执行步骤';
    final detail = _displayText(step['detail']);
    final result = _displayText(step['result']);
    final approvalId = _displayText(step['approvalId']);
    final statusColor = switch (status) {
      'waiting_approval' => colors.primary,
      'failed' || 'denied' || 'expired' => colors.error,
      'succeeded' => colors.tertiary,
      _ => colors.onSurfaceVariant,
    };
    final icon = switch (kind) {
      'approval' => Icons.fact_check_outlined,
      'file_commit' => Icons.save_outlined,
      'subagent' => Icons.account_tree_outlined,
      _ => Icons.build_outlined,
    };
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 5 : 6, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: compact ? 15 : 17, color: statusColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail != null ? '$title · $detail' : title,
                  style: compact
                      ? theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurface,
                        )
                      : theme.textTheme.bodyMedium,
                ),
                Text(
                  [
                    executionStatus(status),
                    ?result,
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (approvalId != null && onOpenApproval != null)
            Icon(
              Icons.chevron_right,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (approvalId != null && onOpenApproval != null)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onOpenApproval!(approvalId),
            child: row,
          )
        else
          row,
        if (!isLast) Divider(height: 1, color: colors.outlineVariant.withValues(alpha: 0.5)),
      ],
    );
  }
}

String? _displayText(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

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
