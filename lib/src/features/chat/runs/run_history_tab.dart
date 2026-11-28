import 'dart:async';
import 'package:material_ui/material_ui.dart';

import '../../../network/api.dart';
import '../chat_controller.dart';
import 'run_timeline.dart';

class RunHistoryTab extends StatefulWidget {
  const RunHistoryTab({
    super.key,
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
  State<RunHistoryTab> createState() => RunHistoryTabState();
}

class RunHistoryTabState extends State<RunHistoryTab>
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
        final timeline = buildRunTimeline(
          context,
          _mergedRuns(),
          stepsOf: widget.chat.stepsOf,
          onOpenApproval: widget.onOpenApproval,
        );
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
                TextButton(onPressed: _load, child: const Text('读取失败，点此重试'))
              else if (_loaded && timeline.isEmpty && !_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 36,
                    horizontal: 12,
                  ),
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
              ...timeline,
              if (_failed && timeline.isNotEmpty)
                TextButton(onPressed: _load, child: const Text('加载失败，点此重试')),
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
}
