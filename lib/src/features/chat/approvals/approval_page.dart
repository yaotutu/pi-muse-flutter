import 'package:material_ui/material_ui.dart';

import '../chat_controller.dart';
import '../runs/execution_display.dart';
import 'approval_preview.dart';

class ApprovalPage extends StatefulWidget {
  const ApprovalPage({
    super.key,
    required this.chat,
    required this.sessionId,
    required this.id,
    required this.pending,
  });

  final ChatController chat;
  final String sessionId;
  final String id;
  final Approval? pending;

  @override
  State<ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends State<ApprovalPage> {
  bool _busy = false;
  bool _unknown = false;
  bool _readFailed = false;
  int? _snapshot;
  int _readRevision = 0;
  int _readTicket = 0;
  bool _reading = false;
  late Approval? _approval = widget.pending;

  bool get _history => widget.pending == null;

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_approvalChanged);
    _approvalChanged();
  }

  @override
  void dispose() {
    widget.chat.removeListener(_approvalChanged);
    super.dispose();
  }

  void _approvalChanged() {
    final chat = widget.chat;
    if (!chat.synchronized) {
      if (_snapshot != null) {
        _readTicket++;
        setState(() {
          _snapshot = null;
          _reading = false;
        });
      }
      return;
    }
    if (_busy || _unknown) return;
    final revision = chat.approvalRevision(widget.id);
    final snapshot = chat.workspaceSnapshot;
    if (_snapshot == snapshot && _readRevision == revision) return;
    final reconnected = _snapshot != snapshot;
    _snapshot = snapshot;
    _readRevision = revision;
    if (_approval == null ||
        revision > _approval!.revision ||
        (reconnected && (_history || chat.approvals[widget.id] == null))) {
      _readApproval();
    }
  }

  Future<void> _readApproval() async {
    if (!widget.chat.synchronized) return;
    final ticket = ++_readTicket;
    setState(() {
      _reading = true;
      _readFailed = false;
    });
    try {
      final approval = await widget.chat.readApprovalDetail(
        widget.sessionId,
        widget.id,
      );
      if (!mounted || ticket != _readTicket) return;
      if (approval.revision < widget.chat.approvalRevision(widget.id)) {
        throw const FormatException('Outdated approval');
      }
      setState(() => _approval = approval);
    } catch (_) {
      if (mounted && ticket == _readTicket) setState(() => _readFailed = true);
    } finally {
      if (mounted && ticket == _readTicket) setState(() => _reading = false);
    }
  }

  bool _actionable(Approval approval) =>
      !_history &&
      !_reading &&
      widget.chat.synchronized &&
      widget.chat.approvals[approval.id]?.revision == approval.revision &&
      approval.expiresAt.isAfter(DateTime.now());

  Future<void> _decide(Approval approval, bool approve) async {
    final snapshot = widget.chat.workspaceSnapshot;
    final confirmed = await confirmApprovalDialog(context, approval, approve);
    if (!mounted ||
        !confirmed ||
        !_actionable(approval) ||
        snapshot != widget.chat.workspaceSnapshot) {
      return;
    }
    await _submit(() => widget.chat.decide(approval, approve));
  }

  Future<void> _submit(Future<Approval> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        _unknown = false;
        _approval = result;
      });
    } catch (_) {
      if (mounted) setState(() => _unknown = true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _approvalChanged();
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.chat,
    builder: (context, _) {
      final approval = _approval;
      if (approval == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('审批详情')),
          body: Center(
            child: !widget.chat.synchronized
                ? const Text('审批状态待同步')
                : _readFailed
                ? TextButton(
                    onPressed: _readApproval,
                    child: const Text('读取失败，点此重试'),
                  )
                : const CircularProgressIndicator(),
          ),
        );
      }
      final needsVerification =
          !_history &&
          (_unknown || widget.chat.approvalNeedsVerification(approval.id));
      final actionable = _actionable(approval);
      final note = needsVerification
          ? '结果未确认，请先核对审批状态。'
          : !widget.chat.synchronized
          ? '审批状态待同步'
          : approval.status != 'pending'
          ? executionStatus(approval.status)
          : !actionable && !_reading
          ? '这项审批已处理或失效。'
          : null;
      final execution = approval.execution;
      return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              _history
                  ? '审批详情'
                  : approval.isFileDiff
                  ? '确认文件修改'
                  : '确认操作',
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SelectionArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      children: [
                        Text(
                          approval.displayTitle,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(approval.scopeOrCategoryLabel),
                        if (executionReceiptText(approval, execution)
                            case final String receipt) ...[
                          const SizedBox(height: 12),
                          Text(receipt),
                          if (execution?['result'] case final String result)
                            Text(result),
                        ],
                        const SizedBox(height: 18),
                        ApprovalPreviewBody(approval: approval),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    children: [
                      if (note != null) Text(note),
                      if (_busy || _reading)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(),
                        )
                      else if (needsVerification)
                        TextButton(
                          onPressed: widget.chat.synchronized
                              ? () => _submit(
                                  () => widget.chat.checkApproval(approval),
                                )
                              : null,
                          child: const Text('核对状态'),
                        )
                      else if (_readFailed)
                        TextButton(
                          onPressed: _readApproval,
                          child: const Text('读取失败，点此重试'),
                        )
                      else if (actionable) ...[
                        OutlinedButton(
                          onPressed: () => _decide(approval, false),
                          child: Text(approval.denyButtonLabel),
                        ),
                        FilledButton(
                          onPressed: () => _decide(approval, true),
                          child: Text(approval.approveButtonLabel),
                        ),
                      ] else
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('返回'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
