import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'subagents.dart';

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
  late final SubagentsClient _client = widget._client ?? SubagentsClient(widget._api);
  List<SubagentSummary>? _subagents;
  Object? _error;
  bool _loading = true;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('专职助手'),
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
              FilledButton(
                onPressed: () => _reload(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final agents = _subagents!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _Card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 20, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '查看系统内置的专职助手能力、系统提示词，编辑关联领域指令，并为支持对话路由的助手按需授权外部 MCP 服务。',
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
          _Card(
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
                          _Pill(
                            label: agent.enabled ? '已启用' : '未启用',
                            background: agent.enabled
                                ? colors.primaryContainer
                                : colors.surfaceContainerHighest,
                            foreground: agent.enabled
                                ? colors.onPrimaryContainer
                                : colors.onSurfaceVariant,
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
                            _Pill(
                              label: '聊天路由',
                              background: colors.secondaryContainer,
                              foreground: colors.onSecondaryContainer,
                            ),
                          if (agent.supportsBackground)
                            _Pill(
                              label: '后台任务',
                              background: colors.surfaceContainerHighest,
                              foreground: colors.onSurfaceVariant,
                            ),
                          _Pill(
                            label: '${agent.tools.length} 个工具',
                            background: colors.surfaceContainerHighest,
                            foreground: colors.onSurfaceVariant,
                          ),
                          if (agent.mcpEditable)
                            _Pill(
                              label: 'MCP ${agent.mcp.length}',
                              background: agent.mcp.isNotEmpty
                                  ? colors.tertiaryContainer
                                  : colors.surfaceContainerHighest,
                              foreground: agent.mcp.isNotEmpty
                                  ? colors.onTertiaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                          if (agent.hasUserInstructions)
                            _Pill(
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

class SubagentDetailPage extends StatefulWidget {
  const SubagentDetailPage({
    super.key,
    required MuseApi api,
    required this.summary,
    SubagentsClient? client,
  }) : _api = api,
       _client = client;

  final MuseApi _api;
  final SubagentsClient? _client;
  final SubagentSummary summary;

  @override
  State<SubagentDetailPage> createState() => _SubagentDetailPageState();
}

class _SubagentDetailPageState extends State<SubagentDetailPage> {
  late final SubagentsClient _client = widget._client ?? SubagentsClient(widget._api);
  SubagentDetail? _detail;
  SubagentMcpSelection? _mcpSelection;
  Object? _error;
  bool _loading = true;
  bool _savingMcp = false;
  bool _savingInstructions = false;
  bool _instructionsDirty = false;
  late final TextEditingController _instructionsController;

  @override
  void initState() {
    super.initState();
    _instructionsController = TextEditingController();
    _reload();
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _reload({bool preserveDraft = false}) async {
    if (_detail == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _client.getDetail(widget.summary.id),
        _client.getMcpSelection(widget.summary.id),
      ]);
      if (!mounted) return;
      final detail = results[0] as SubagentDetail;
      final selection = results[1] as SubagentMcpSelection;
      if (!preserveDraft && detail.userInstructions != null) {
        _instructionsController.text = detail.userInstructions!.instructions;
        _instructionsDirty = false;
      }
      setState(() {
        _detail = detail;
        _mcpSelection = selection;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (_detail == null) {
        setState(() {
          _error = error;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        _showMessage(subagentErrorMessage(error));
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleMcpServer(String serverName, bool enabled) async {
    final selection = _mcpSelection;
    if (selection == null || _savingMcp) return;
    final next = Set<String>.from(selection.enabledServers);
    if (enabled) {
      next.add(serverName);
    } else {
      next.remove(serverName);
    }
    final sorted = next.toList()..sort();
    setState(() => _savingMcp = true);
    try {
      final updated = await _client.updateMcpSelection(
        widget.summary.id,
        sorted,
      );
      if (!mounted) return;
      setState(() {
        _mcpSelection = updated;
        _savingMcp = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingMcp = false);
      _showMessage(subagentErrorMessage(error));
    }
  }

  Future<void> _saveInstructions() async {
    final detail = _detail;
    final current = detail?.userInstructions;
    if (detail == null || current == null || _savingInstructions) return;
    setState(() => _savingInstructions = true);
    try {
      final updated = await _client.updateUserInstructions(
        detail.summary.id,
        _instructionsController.text,
        current.path,
      );
      if (!mounted) return;
      _instructionsController.text = updated.instructions;
      setState(() {
        _detail = SubagentDetail(
          summary: detail.summary,
          prompts: detail.prompts,
          userInstructions: updated,
        );
        _instructionsDirty = false;
        _savingInstructions = false;
      });
      _showMessage('已保存领域指令');
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingInstructions = false);
      _showMessage(subagentErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_detail?.summary.name ?? widget.summary.name),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _reload(preserveDraft: _instructionsDirty),
            tooltip: '刷新详情',
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
    if (_loading && _detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _detail == null) {
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
              FilledButton(
                onPressed: () => _reload(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final detail = _detail!;
    final summary = detail.summary;
    final selection = _mcpSelection!;
    final instructions = detail.userInstructions;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('概览与运行策略', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(summary.description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Pill(
                    label: summary.enabled ? '已启用' : '未启用',
                    background: summary.enabled
                        ? colors.primaryContainer
                        : colors.surfaceContainerHighest,
                    foreground: summary.enabled
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                  if (summary.supportsChat)
                    _Pill(
                      label: '支持聊天路由',
                      background: colors.secondaryContainer,
                      foreground: colors.onSecondaryContainer,
                    ),
                  if (summary.supportsBackground)
                    _Pill(
                      label: '支持后台任务',
                      background: colors.surfaceContainerHighest,
                      foreground: colors.onSurfaceVariant,
                    ),
                  _Pill(
                    label: '无跨次上下文',
                    background: colors.surfaceContainerHighest,
                    foreground: colors.onSurfaceVariant,
                  ),
                  _Pill(
                    label: summary.parallelAllowed ? '允许并发' : '独占串行',
                    background: colors.surfaceContainerHighest,
                    foreground: colors.onSurfaceVariant,
                  ),
                ],
              ),
              if (summary.routingHint != null) ...[
                const SizedBox(height: 12),
                Text(
                  '主聊天路由说明',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary.routingHint!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'MCP 服务权限',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (_savingMcp)
                          const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selection.editable
                          ? '默认对所有专职助手关闭。仅开启此处列表中的服务后，该助手才可在聊天任务中使用对应 MCP 工具。'
                          : '该助手仅在后台执行固定结构化任务，暂不支持绑定外部 MCP 服务。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selection.editable && selection.servers.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    '暂无全局 MCP 服务，请先在「设置 → MCP 服务」中添加。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              else if (selection.editable)
                for (final server in selection.servers) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: Text(server.name),
                    subtitle: Text(
                      [
                        '${server.transport.label} · ${server.status.label} · ${server.toolCount} 个工具',
                        if (!server.globalEnabled) '全局已停用（需在 MCP 服务总开关启用后生效）',
                        if (server.description.isNotEmpty) server.description,
                      ].join('\n'),
                    ),
                    isThreeLine:
                        !server.globalEnabled && server.description.isNotEmpty,
                    value: server.enabled,
                    onChanged: _savingMcp
                        ? null
                        : (val) => _toggleMcpServer(server.name, val),
                  ),
                ],
            ],
          ),
        ),
        if (summary.hasUserInstructions && instructions != null) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '领域用户指令',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    _Pill(
                      label: instructions.path,
                      background: colors.surfaceContainerHighest,
                      foreground: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _instructionsController,
                  enabled: summary.userInstructionsEditable && !_savingInstructions,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 20000,
                  onChanged: (_) {
                    final dirty =
                        _instructionsController.text != instructions.instructions;
                    if (dirty != _instructionsDirty) {
                      setState(() => _instructionsDirty = dirty);
                    }
                  },
                  decoration: const InputDecoration(
                    hintText: '输入仅作用于该助手领域的显式偏好与规则…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed:
                        (_instructionsDirty &&
                            !_savingInstructions &&
                            summary.userInstructionsEditable)
                        ? _saveInstructions
                        : null,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(_savingInstructions ? '保存中…' : '保存指令'),
                  ),
                ),
                if (instructions.habits.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      '已归纳行为习惯（${instructions.habits.length}）',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    children: [
                      for (final habit in instructions.habits)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.auto_awesome_outlined,
                            size: 16,
                            color: colors.primary,
                          ),
                          title: Text(habit.text),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Card(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            title: Text(
              '内置工具（${summary.tools.length}）',
              style: theme.textTheme.titleMedium,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              for (final tool in summary.tools)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            tool.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          for (final trigger in tool.triggers)
                            _Pill(
                              label: trigger == 'chat' ? '聊天' : '后台',
                              background: colors.surfaceContainerHighest,
                              foreground: colors.onSurfaceVariant,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
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
        const SizedBox(height: 12),
        _Card(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text('系统提示词（只读）', style: theme.textTheme.titleMedium),
              ),
              for (final section in detail.prompts) ...[
                const Divider(height: 1),
                ExpansionTile(
                  title: Text(section.label),
                  subtitle: Text(
                    '${section.trigger == 'chat' ? '聊天路由' : '后台任务'} · ${section.sourcePath}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        section.content,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final body = Padding(padding: padding, child: child);
    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
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
