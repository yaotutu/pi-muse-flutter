import 'package:material_ui/material_ui.dart';

import '../chat_controller.dart';
import '../runs/execution_display.dart';
import 'approval_preview.dart';

class ChatApprovalCard extends StatefulWidget {
  const ChatApprovalCard({
    super.key,
    required this.chat,
    required this.approval,
    required this.onOpenDetails,
  });

  final ChatController chat;
  final Approval approval;
  final VoidCallback onOpenDetails;

  @override
  State<ChatApprovalCard> createState() => _ChatApprovalCardState();
}

class _ChatApprovalCardState extends State<ChatApprovalCard> {
  late bool _expanded =
      widget.approval.isProposal ||
      (widget.approval.before.length + widget.approval.after.length <= 240);
  bool _busy = false;
  bool _unknown = false;

  bool get _actionable =>
      widget.approval.status == 'pending' &&
      widget.chat.synchronized &&
      widget.chat.approvals[widget.approval.id]?.revision ==
          widget.approval.revision &&
      widget.approval.expiresAt.isAfter(DateTime.now());

  Future<void> _decide(bool approve) async {
    final approval = widget.approval;
    final snapshot = widget.chat.workspaceSnapshot;
    final confirmed = await confirmApprovalDialog(context, approval, approve);
    if (!mounted ||
        !confirmed ||
        !_actionable ||
        snapshot != widget.chat.workspaceSnapshot) {
      return;
    }
    await _run(() => widget.chat.decide(approval, approve));
  }

  Future<void> _run(Future<Approval> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _unknown = false);
    } catch (_) {
      if (mounted) setState(() => _unknown = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final approval = widget.approval;
    final isPending = approval.status == 'pending';
    final needsVerify =
        isPending &&
        (_unknown || widget.chat.approvalNeedsVerification(approval.id));
    final receipt = executionReceiptText(approval, approval.execution);
    final statusText = isPending
        ? (approval.expiresAt.isAfter(DateTime.now()) ? '待你确认' : '已过期，等待同步')
        : executionStatus(approval.status);
    final borderColor = isPending ? colors.primary : colors.outlineVariant;
    final surfaceColor = isPending
        ? colors.primaryContainer.withValues(alpha: 0.25)
        : colors.surfaceContainerLow;
    final statusColor = switch (approval.status) {
      'pending' => colors.primary,
      'approved' => colors.tertiary,
      'denied' || 'expired' => colors.error,
      _ => colors.onSurfaceVariant,
    };

    return Material(
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: isPending ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  approval.isProposal
                      ? Icons.fact_check_outlined
                      : Icons.edit_note_rounded,
                  size: 20,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    approval.displayTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    child: Text(
                      statusText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                approval.scopeOrCategoryLabel,
                if (approval.targetLabel case final String target
                    when target != approval.displayTitle)
                  target,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (receipt != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  receipt,
                  if (approval.execution?['result'] case final String detail
                      when detail.isNotEmpty)
                    detail,
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
              ),
            ],
            if (_expanded) ...[
              const SizedBox(height: 10),
              ApprovalPreviewBody(approval: approval, compact: true),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (approval.isFileDiff)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? '收起对比' : '展开完整对比'),
                  ),
                TextButton(
                  onPressed: widget.onOpenDetails,
                  child: const Text('查看全文'),
                ),
                if (_busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (needsVerify)
                  TextButton(
                    onPressed: widget.chat.synchronized
                        ? () => _run(() => widget.chat.checkApproval(approval))
                        : null,
                    child: const Text('核对状态'),
                  )
                else if (_actionable) ...[
                  OutlinedButton(
                    onPressed: () => _decide(false),
                    child: Text(approval.denyButtonLabel),
                  ),
                  FilledButton(
                    onPressed: () => _decide(true),
                    child: Text(approval.approveButtonLabel),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
