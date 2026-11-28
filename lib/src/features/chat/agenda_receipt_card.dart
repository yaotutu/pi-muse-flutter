import 'package:material_ui/material_ui.dart';

import '../../shared/agenda_moment.dart';
import '../../shared/agenda_receipt.dart';

/// 聊天里的事项卡片。
///
/// 卡片只展示服务端回执里的快照，修改一律回到事项详情页按 ID 读取权威状态。
class AgendaReceiptCard extends StatelessWidget {
  const AgendaReceiptCard({
    super.key,
    required this.receipt,
    this.onOpen,
    this.onEditTime,
  });

  final AgendaReceipt receipt;
  final VoidCallback? onOpen;
  final VoidCallback? onEditTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final moment = parseAgendaMoment(receipt.when, zoneName: receipt.timeZone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_note_outlined,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    receipt.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              receipt.title,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSurface,
              ),
            ),
            if (moment != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  formatAgendaMoment(context, moment),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onOpen,
                  child: const Text('查看事项'),
                ),
                TextButton(
                  onPressed: onEditTime,
                  child: const Text('修改时间'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
