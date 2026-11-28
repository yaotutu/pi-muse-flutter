import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../network/api.dart';
import '../chat_controller.dart';

Future<bool> confirmApprovalDialog(
  BuildContext context,
  Approval approval,
  bool approve,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        approve
            ? (approval.isFileDiff ? '批准这次修改？' : '确认执行该操作？')
            : (approval.isFileDiff ? '拒绝这次修改？' : '拒绝该请求？'),
      ),
      content: Text(approval.targetLabel ?? approval.displayTitle),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(approve ? '确认批准' : '确认拒绝'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

String? executionReceiptText(Approval approval, Json? execution) {
  if (approval.status != 'approved' && execution == null) return null;
  if (approval.isFileDiff) {
    return switch (execution?['status']) {
      'running' => '文件提交中',
      'succeeded' => '文件已写入',
      'failed' => '文件写入失败',
      'cancelled' => '文件写入已取消',
      'unknown' => '文件写入结果待核对',
      _ => '尚未收到文件执行回执',
    };
  }
  return switch (execution?['status']) {
    'running' => '执行中',
    'succeeded' => '已执行',
    'failed' => '执行失败',
    'cancelled' => '已取消',
    'unknown' => '执行结果待核对',
    _ => null,
  };
}

class ApprovalPreviewBody extends StatelessWidget {
  const ApprovalPreviewBody({
    super.key,
    required this.approval,
    this.compact = false,
  });

  final Approval approval;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (approval.isFileDiff) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact && approval.path.isNotEmpty) ...[
            Text(
              approval.path,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _FileText(
            label: '修改前',
            content: approval.beforeExists ? approval.before : null,
          ),
          const SizedBox(height: 12),
          _FileText(label: '修改后', content: approval.after),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (approval.summary.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(approval.summary, style: theme.textTheme.bodyMedium),
            ),
          ),
        if (approval.target case final String target
            when target.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '影响目标：$target',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        if (approval.items.isNotEmpty) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < approval.items.length; i++) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${approval.items[i].label}：',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            approval.items[i].value,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    if (i != approval.items.length - 1)
                      const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FileText extends StatelessWidget {
  const _FileText({required this.label, required this.content});

  final String label;
  final String? content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
                if (content?.isNotEmpty == true)
                  IconButton(
                    tooltip: '复制$label全文',
                    icon: const Icon(Icons.content_copy, size: 18),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: content!)),
                  ),
              ],
            ),
            Text(
              content == null
                  ? '新建文件'
                  : content!.isEmpty
                  ? '空文件'
                  : content!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
