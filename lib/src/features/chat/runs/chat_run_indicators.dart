import 'package:material_ui/material_ui.dart';

import '../../../network/api.dart';

class LiveRunStepBar extends StatelessWidget {
  const LiveRunStepBar({
    super.key,
    required this.run,
    required this.steps,
    required this.onOpenDetails,
  });

  final Json? run;
  final List<Json> steps;
  final VoidCallback onOpenDetails;

  String _latestRecordText() {
    if (steps.isNotEmpty) {
      Json? pick = steps
          .where((s) => s['status'] == 'waiting_approval')
          .lastOrNull;
      pick ??= steps.where((s) => s['status'] == 'running').lastOrNull;
      if (pick == null) {
        final last = steps.last;
        if (last['kind'] == 'file_commit' && steps.length >= 2) {
          final prev = steps[steps.length - 2];
          final prevTool = prev['toolName'];
          if (prev['kind'] == 'tool' &&
              (prevTool == 'write' || prevTool == 'edit') &&
              prev['detail'] == last['detail']) {
            pick = prev;
          }
        }
        pick ??= last;
      }
      final title = pick['title'] as String?;
      final detail = pick['detail'] as String?;
      final text = [
        if (title != null && title.isNotEmpty) title else '正在执行',
        if (detail != null && detail.isNotEmpty) detail,
      ].join(' · ');
      return pick['status'] == 'waiting_approval' ? '等待审批 · $text' : text;
    }
    final tools = (run?['tools'] as List? ?? const []).cast<Json>();
    if (tools.isNotEmpty) {
      final label = tools.last['label'] as String?;
      if (label != null && label.isNotEmpty) return label;
    }
    final subagents = (run?['subagents'] as List? ?? const []).cast<Json>();
    if (subagents.isNotEmpty) {
      final role = subagents.last['role'] as String?;
      if (role != null && role.isNotEmpty) return '委派子代理 · $role';
    }
    final rawLabel = run?['label'];
    if (rawLabel is String && rawLabel.isNotEmpty) return rawLabel;
    return '助手正在处理中…';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final waitingApproval = steps.any((s) => s['status'] == 'waiting_approval');
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: waitingApproval
              ? colors.primary.withValues(alpha: 0.45)
              : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpenDetails,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                waitingApproval
                    ? Icons.fact_check_outlined
                    : Icons.hourglass_top_rounded,
                size: 16,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _latestRecordText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                steps.length > 1 ? '共 ${steps.length} 步' : '全部动态',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TerminalRunNotice extends StatelessWidget {
  const TerminalRunNotice({super.key, required this.status, this.label});

  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cancelled = status == 'cancelled';
    final customLabel = label?.trim();
    final message = cancelled
        ? (customLabel != null &&
                  customLabel.isNotEmpty &&
                  customLabel != '执行已停止'
              ? customLabel
              : '上一轮回复已停止')
        : (customLabel != null &&
                  customLabel.isNotEmpty &&
                  customLabel != '执行失败'
              ? customLabel
              : '上一轮回复未能完成，你可以重新发送或继续对话');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              cancelled ? Icons.stop_circle_outlined : Icons.info_outline,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
