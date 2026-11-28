import 'dart:async';
import 'package:material_ui/material_ui.dart';

import '../../../network/api.dart';
import '../chat_controller.dart';
import '../runs/execution_display.dart';

class ApprovalsTab extends StatefulWidget {
  const ApprovalsTab({
    super.key,
    required this.chat,
    required this.sessionId,
    required this.onOpen,
  });

  final ChatController chat;
  final String sessionId;
  final void Function(String, Approval?) onOpen;

  @override
  State<ApprovalsTab> createState() => _ApprovalsTabState();
}

class _ApprovalsTabState extends State<ApprovalsTab>
    with AutomaticKeepAliveClientMixin {
  bool _approvalHistory = false;
  String _approvalStatus = '';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
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
                  onOpen: (id) => widget.onOpen(id, null),
                )
              : ListenableBuilder(
                  listenable: widget.chat,
                  builder: (context, _) {
                    if (!widget.chat.synchronized) {
                      return const Center(child: Text('审批状态待同步'));
                    }
                    final items = widget.chat.sessionApprovals(
                      widget.sessionId,
                    );
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
                          subtitle:
                              target != null && target != item.displayTitle
                              ? Text(target)
                              : null,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => widget.onOpen(item.id, item),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
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
