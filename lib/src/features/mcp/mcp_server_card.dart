import 'package:material_ui/material_ui.dart';

import 'mcp_models.dart';
import 'mcp_section_card.dart';

class McpServerCard extends StatelessWidget {
  const McpServerCard({
    super.key,
    required this.server,
    required this.assistantServer,
    required this.busy,
    required this.onEnable,
    required this.onToggleAssistant,
    required this.onReconnect,
    required this.onEdit,
    required this.onDelete,
  });

  final McpServer server;
  final McpAssistantServer? assistantServer;
  final bool busy;
  final VoidCallback onEnable;
  final ValueChanged<bool> onToggleAssistant;
  final VoidCallback onReconnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final assistantEnabled = assistantServer?.enabled ?? true;

    final (statusBg, statusFg) = switch (server.status) {
      McpConnectionStatus.connected => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      McpConnectionStatus.error => (
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      McpConnectionStatus.connecting => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      McpConnectionStatus.disabled || McpConnectionStatus.disconnected => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };

    final endpointText = server.transport == McpTransport.http
        ? (server.url ?? '')
        : [server.command ?? '', ...server.args].join(' ').trim();

    return McpSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        server.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    _PillBadge(
                      label: server.status.label,
                      background: statusBg,
                      foreground: statusFg,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _PillBadge(
                      label: server.transport.label,
                      background: colors.surfaceContainerHighest,
                      foreground: colors.onSurfaceVariant,
                    ),
                    _PillBadge(
                      label: '${server.toolCount} 个工具',
                      background: colors.surfaceContainerHighest,
                      foreground: colors.onSurfaceVariant,
                    ),
                    _PillBadge(
                      label: '超时 ${server.timeout}s',
                      background: colors.surfaceContainerHighest,
                      foreground: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                if (server.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(server.description, style: theme.textTheme.bodyMedium),
                ],
                if (endpointText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    endpointText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (server.headerNames.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '请求头键：${server.headerNames.join('、')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (server.envKeys.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '环境变量键：${server.envKeys.join('、')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (server.error != null && server.error!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.errorContainer.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: colors.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              server.error!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('聊天可用'),
            subtitle: Text(
              !server.enabled
                  ? '服务端配置中已停用'
                  : assistantEnabled
                  ? '聊天默认开启，可随时关闭'
                  : '已对聊天关闭，不影响 Subagent 按需开启',
            ),
            value: assistantEnabled,
            onChanged: (!server.enabled || busy) ? null : onToggleAssistant,
          ),
          if (server.tools.isNotEmpty) ...[
            const Divider(height: 1),
            ExpansionTile(
              title: Text(
                '可用工具（${server.tools.length}）',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (final tool in server.tools)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.build_outlined,
                          size: 15,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tool.name,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (tool.description.isNotEmpty)
                                Text(
                                  tool.description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (!server.enabled)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onEnable,
                    icon: const Icon(Icons.play_arrow_outlined, size: 18),
                    label: const Text('启用服务'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: busy ? null : onReconnect,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重连'),
                  ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : onDelete,
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w500,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(label, style: style),
      ),
    );
  }
}
