import 'package:material_ui/material_ui.dart';

import '../../network/api.dart';
import 'subagent_detail_page.dart';
import 'subagent_widgets.dart';
import 'subagents_client.dart';
import 'subagent_models.dart';

class SubagentsPage extends StatefulWidget {
  const SubagentsPage({
    super.key,
    required MuseApi api,
    SubagentsClient? client,
  }) : _api = api,
       _client = client;

  final MuseApi _api;
  final SubagentsClient? _client;

  @override
  State<SubagentsPage> createState() => _SubagentsPageState();
}

class _SubagentsPageState extends State<SubagentsPage> {
  late final SubagentsClient _client =
      widget._client ?? SubagentsClient(widget._api);
  List<SubagentSummary>? _subagents;
  Object? _error;
  bool _loading = true;
  final Set<String> _toggling = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload({bool showSpinner = true}) async {
    if (showSpinner && _subagents == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _client.list();
      if (!mounted) return;
      setState(() {
        _subagents = list;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (_subagents == null) {
        setState(() {
          _error = error;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(subagentErrorMessage(error))));
      }
    }
  }

  Future<void> _openDetail(SubagentSummary summary) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SubagentDetailPage(
          api: widget._api,
          client: _client,
          summary: summary,
        ),
      ),
    );
    if (mounted) {
      await _reload(showSpinner: false);
    }
  }

  Future<void> _toggleEnabled(SubagentSummary agent, bool enabled) async {
    if (_toggling.contains(agent.id)) return;
    setState(() => _toggling.add(agent.id));
    try {
      final updated = await _client.setEnabled(agent.id, enabled);
      if (!mounted) return;
      setState(() {
        final current = _subagents;
        if (current != null) {
          _subagents = [
            for (final item in current)
              if (item.id == agent.id) updated.summary else item,
          ];
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(subagentErrorMessage(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _toggling.remove(agent.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subagent'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _reload(showSpinner: false),
            tooltip: '刷新列表',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: _buildBody(theme, colors),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colors) {
    if (_loading && _subagents == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _subagents == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: colors.error),
              const SizedBox(height: 12),
              Text(
                subagentErrorMessage(_error!),
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => _reload(), child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final agents = _subagents!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        SubagentCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 20, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '查看系统内置的 Subagent 能力与系统提示词，编辑关联领域指令，并为支持对话路由的 Subagent 按需开启 MCP 服务。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final agent in agents) ...[
          SubagentCard(
            onTap: () => _openDetail(agent),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              agent.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Switch(
                            value: agent.enabled,
                            onChanged:
                                (!agent.enabledEditable ||
                                    _toggling.contains(agent.id))
                                ? null
                                : (val) => _toggleEnabled(agent, val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        agent.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (agent.supportsChat)
                            SubagentPill(
                              label: '聊天路由',
                              background: colors.secondaryContainer,
                              foreground: colors.onSecondaryContainer,
                            ),
                          if (agent.supportsBackground)
                            SubagentPill(
                              label: '后台任务',
                              background: colors.surfaceContainerHighest,
                              foreground: colors.onSurfaceVariant,
                            ),
                          SubagentPill(
                            label: '${agent.tools.length} 个工具',
                            background: colors.surfaceContainerHighest,
                            foreground: colors.onSurfaceVariant,
                          ),
                          if (agent.mcpEditable)
                            SubagentPill(
                              label: 'MCP ${agent.mcp.length}',
                              background: agent.mcp.isNotEmpty
                                  ? colors.tertiaryContainer
                                  : colors.surfaceContainerHighest,
                              foreground: agent.mcp.isNotEmpty
                                  ? colors.onTertiaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                          if (agent.hasUserInstructions)
                            SubagentPill(
                              label: '可编领域指令',
                              background: colors.surfaceContainerHighest,
                              foreground: colors.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
