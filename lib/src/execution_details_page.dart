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
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (_visited.add(_tabs.index)) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openActivity(String id) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ActivityPage(
          chat: widget.chat,
          sessionId: widget.sessionId,
          id: id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('执行详情'),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: '动态'),
          Tab(text: '审批'),
          Tab(text: '历史'),
        ],
      ),
    ),
    body: SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                ListenableBuilder(listenable: widget.chat, builder: _buildRuns),
                if (_visited.contains(1))
                  _buildApprovals()
                else
                  const SizedBox(),
                if (_visited.contains(2))
                  _HistoryList(
                    chat: widget.chat,
                    sessionId: widget.sessionId,
                    onOpen: _openActivity,
                  )
                else
                  const SizedBox(),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildRuns(BuildContext context, Widget? child) {
    final chat = widget.chat;
    if (!chat.synchronized) return const Center(child: Text('执行状态待同步'));
    final runs = chat.executionRuns(widget.sessionId);
    final pending = chat.sessionApprovals(widget.sessionId);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pending.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text('等待你的审批（${pending.length} 项）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _tabs.animateTo(1),
          ),
        if (runs.isEmpty) const ListTile(title: Text('当前没有正在执行的工作')),
        for (final run in runs)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _displayText(run['title']) ??
                        (run['source'] == 'job' ? '定时任务' : '聊天执行'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    _displayText(run['label']) ??
                        executionStatus(run['status']),
                  ),
                  for (final tool
                      in (run['tools'] as List? ?? const []).cast<Json>())
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.build_outlined),
                      title: Text(_displayText(tool['label']) ?? '工具'),
                      subtitle: Text(executionStatus(tool['status'])),
                    ),
                  for (final agent
                      in (run['subagents'] as List? ?? const []).cast<Json>())
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_tree_outlined),
                      title: Text(_displayText(agent['role']) ?? '子任务'),
                      subtitle: Text(
                        _displayText(agent['label']) ??
                            executionStatus(agent['status']),
                      ),
                    ),
                  if (run['activityId'] case final String id)
                    TextButton(
                      onPressed: () => _openActivity(id),
                      child: const Text('查看活动详情'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

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
            ? _HistoryList(
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
                    return const Center(child: Text('当前没有待审批的修改'));
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(item.title ?? item.path),
                        subtitle: item.title == null ? null : Text(item.path),
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

class _HistoryList extends StatefulWidget {
  const _HistoryList({
    super.key,
    required this.chat,
    required this.sessionId,
    required this.onOpen,
    this.approvalStatus,
  });

  final ChatController chat;
  final String sessionId;
  final ValueChanged<String> onOpen;
  final String? approvalStatus;

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList>
    with AutomaticKeepAliveClientMixin {
  final _items = <String, Json>{};
  (int, int)? _version;
  bool _loading = false;
  bool _failed = false;
  bool _loaded = false;
  String? _cursor;
  int _request = 0;

  bool get _approvals => widget.approvalStatus != null;
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
      approvals: _approvals,
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
      final collection = _approvals ? 'approvals' : 'activities';
      final data = await widget.chat.readExecution(
        '/api/$collection',
        query: {
          'sessionId': widget.sessionId,
          'cursor': ?cursor,
          if (widget.approvalStatus case final String status
              when status.isNotEmpty)
            'status': status,
        },
      );
      if (!mounted || request != _request) return;
      final rows = (data[collection] as List).cast<Json>();
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
              leading: Icon(
                _approvals ? Icons.description_outlined : Icons.history,
              ),
              title: Text(row['title'] as String),
              subtitle: Text(executionStatus(row['status'])),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => widget.onOpen(row['id'] as String),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_failed)
            TextButton(onPressed: _load, child: const Text('读取失败，点此重试'))
          else if (_loaded && _items.isEmpty && !_loading)
            ListTile(title: Text(_approvals ? '暂无已处理的审批' : '暂无登记活动')),
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

class _ActivityPage extends StatefulWidget {
  const _ActivityPage({
    required this.chat,
    required this.sessionId,
    required this.id,
  });

  final ChatController chat;
  final String sessionId;
  final String id;

  @override
  State<_ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<_ActivityPage> {
  Future<Json>? _data;
  (int, int)? _version;

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
      if (_version != null) setState(() => _version = null);
      return;
    }
    final version = widget.chat.executionHistoryVersion(
      widget.sessionId,
      approvals: false,
    );
    if (_version == version) return;
    _version = version;
    _reload();
  }

  void _reload() {
    final read = _read();
    setState(() {
      _data = read;
    });
  }

  Future<Json> _read() async {
    final data = await widget.chat.readExecution(
      '/api/activities/${Uri.encodeComponent(widget.id)}',
    );
    final activity = data['activity'] as Json;
    if (activity['sessionId'] != widget.sessionId ||
        activity['id'] != widget.id) {
      throw const FormatException('Unexpected activity');
    }
    return data;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('活动详情'),
      actions: [
        IconButton(
          tooltip: '刷新活动详情',
          onPressed: widget.chat.synchronized ? _reload : null,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<Json>(
        future: widget.chat.synchronized ? _data : null,
        builder: (context, snapshot) {
          if (!widget.chat.synchronized) {
            return const Center(child: Text('活动状态待同步'));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return Center(
              child: TextButton(
                onPressed: _reload,
                child: const Text('读取失败，点此重试'),
              ),
            );
          }
          final activity = data['activity'] as Json;
          final steps = (data['steps'] as List).cast<Json>();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                activity['title'] as String,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(executionStatus(activity['status'])),
              for (final (field, label) in [
                ('goal', '目标'),
                ('deliverable', '交付'),
                ('progress', '进度'),
                ('result', '结果'),
              ])
                if (_displayText(activity[field]) case final String text)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    subtitle: Text(text),
                  ),
              const Divider(),
              Text('执行步骤', style: Theme.of(context).textTheme.titleMedium),
              if (steps.isEmpty) const Text('暂无执行步骤'),
              for (final step in steps)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(step['title'] as String),
                  subtitle: Text(
                    [
                      executionStatus(step['status']),
                      if (_displayText(step['result']) case final String result)
                        result,
                    ].join('\n'),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
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
