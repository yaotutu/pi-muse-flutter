import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'mcp.dart';

class McpPage extends StatefulWidget {
  const McpPage({super.key, required MuseApi api, McpClient? client})
    : _api = api,
      _client = client;

  final MuseApi _api;
  final McpClient? _client;

  @override
  State<McpPage> createState() => _McpPageState();
}

class _McpPageState extends State<McpPage> {
  late final McpClient _client = widget._client ?? McpClient(widget._api);
  McpOverview? _overview;
  Object? _loadError;
  bool _loading = true;
  final Set<String> _pending = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload({bool showSpinner = true}) async {
    if (showSpinner && _overview == null) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final data = await _client.loadOverview();
      if (!mounted) return;
      setState(() {
        _overview = data;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (_overview == null) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        _showMessage(mcpErrorMessage(error));
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runServerAction(
    String name,
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_pending.contains(name)) return;
    setState(() => _pending.add(name));
    try {
      await action();
      await _reload(showSpinner: false);
      if (successMessage != null) _showMessage(successMessage);
    } catch (error) {
      _showMessage(mcpErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _pending.remove(name));
      }
    }
  }

  Future<void> _enableServer(McpServer server) => _runServerAction(
    server.name,
    () => _client.patchServer(server.name, enabled: true),
    successMessage: '已启用 ${server.name}',
  );

  Future<void> _toggleAssistantEnabled(McpServer server, bool enabled) {
    final overview = _overview;
    if (overview == null) return Future.value();
    final nextOverrides = Map<String, bool>.from(overview.assistantOverrides);
    for (final existing in overview.servers) {
      nextOverrides.putIfAbsent(
        existing.name,
        () => overview.assistantServers[existing.name]?.enabled ?? true,
      );
    }
    nextOverrides[server.name] = enabled;
    return _runServerAction(
      server.name,
      () => _client.updateAssistantOverrides(nextOverrides),
    );
  }

  Future<void> _confirmDelete(McpServer server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${server.name}」？'),
        content: const Text('删除后将立即断开连接，并从全局列表与已开启该服务的 Subagent 中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runServerAction(
      server.name,
      () => _client.deleteServer(server.name),
      successMessage: '已删除 ${server.name}',
    );
  }

  Future<void> _openEditor([McpServer? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _McpServerEditorPage(client: _client, existing: existing),
      ),
    );
    if (changed == true && mounted) {
      await _reload(showSpinner: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP 服务'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _reload(showSpinner: false),
            tooltip: '刷新状态',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => _openEditor(),
            tooltip: '添加 MCP 服务',
            icon: const Icon(Icons.add),
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
    if (_loading && _overview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _overview == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: colors.error),
              const SizedBox(height: 12),
              Text(
                mcpErrorMessage(_loadError!),
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

    final overview = _overview!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _SectionCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 20, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '这里维护全局 MCP 服务列表。新增服务默认对聊天开启、对 Subagent 关闭；可在此单独控制聊天是否使用，或在「Subagent」中按需开启。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (overview.diagnostics.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            color: colors.errorContainer.withValues(alpha: 0.45),
            borderColor: colors.error.withValues(alpha: 0.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '配置诊断',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.error,
                  ),
                ),
                const SizedBox(height: 6),
                for (final diag in overview.diagnostics)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${diag.server}：${diag.message}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (overview.servers.isEmpty)
          _SectionCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Icon(
                    Icons.extension_outlined,
                    size: 40,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text('尚未配置 MCP 服务', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    '支持远程 Streamable HTTP 与本地命令行 (stdio) MCP 服务。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add),
                    label: const Text('添加 MCP 服务'),
                  ),
                ],
              ),
            ),
          )
        else
          for (final server in overview.servers) ...[
            _McpServerCard(
              server: server,
              assistantServer: overview.assistantServers[server.name],
              busy: _pending.contains(server.name),
              onEnable: () => _enableServer(server),
              onToggleAssistant: (value) =>
                  _toggleAssistantEnabled(server, value),
              onReconnect: () => _runServerAction(
                server.name,
                () => _client.reconnectServer(server.name),
                successMessage: '已触发重连 ${server.name}',
              ),
              onEdit: () => _openEditor(server),
              onDelete: () => _confirmDelete(server),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _McpServerCard extends StatelessWidget {
  const _McpServerCard({
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

    return _SectionCard(
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

class _KeyValueEntry {
  _KeyValueEntry([String key = '', String value = ''])
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;
  bool obscure = true;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class _McpServerEditorPage extends StatefulWidget {
  const _McpServerEditorPage({required this.client, this.existing});

  final McpClient client;
  final McpServer? existing;

  @override
  State<_McpServerEditorPage> createState() => _McpServerEditorPageState();
}

class _McpServerEditorPageState extends State<_McpServerEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _urlController;
  late final TextEditingController _commandController;
  late final TextEditingController _argsController;
  late final TextEditingController _cwdController;

  late McpTransport _transport;
  late bool _replaceConnection;
  final List<_KeyValueEntry> _headers = [];
  final List<_KeyValueEntry> _envs = [];
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _timeoutController = TextEditingController(
      text: (existing?.timeout ?? 60).toString(),
    );
    _urlController = TextEditingController(text: existing?.url ?? '');
    _commandController = TextEditingController(text: existing?.command ?? '');
    _argsController = TextEditingController(
      text: existing?.args.join('\n') ?? '',
    );
    _cwdController = TextEditingController(text: existing?.cwd ?? '');
    _transport = existing?.transport ?? McpTransport.http;
    _replaceConnection = existing == null;
    if (existing != null) {
      for (final key in existing.headerNames) {
        _headers.add(_KeyValueEntry(key));
      }
      for (final key in existing.envKeys) {
        _envs.add(_KeyValueEntry(key));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _timeoutController.dispose();
    _urlController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    _cwdController.dispose();
    for (final entry in _headers) {
      entry.dispose();
    }
    for (final entry in _envs) {
      entry.dispose();
    }
    super.dispose();
  }

  Map<String, String>? _collectMap(
    List<_KeyValueEntry> entries,
    String label,
  ) {
    final map = <String, String>{};
    for (final entry in entries) {
      final k = entry.keyController.text.trim();
      final v = entry.valueController.text;
      if (k.isEmpty && v.isEmpty) continue;
      if (k.isEmpty) {
        throw FormatException('$label 存在空键名，请补全或删除空行');
      }
      map[k] = v;
    }
    return map.isEmpty ? null : map;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final description = _descriptionController.text.trim();
      final timeout = int.parse(_timeoutController.text.trim());
      final existing = widget.existing;
      if (existing != null && !_replaceConnection) {
        await widget.client.patchServer(
          existing.name,
          description: description,
          timeout: timeout,
        );
      } else {
        final name = existing?.name ?? _nameController.text.trim();
        final body = <String, dynamic>{
          'type': _transport == McpTransport.http ? 'http' : 'stdio',
          'enabled': true,
          'timeout': timeout,
          if (description.isNotEmpty) 'description': description,
        };
        if (_transport == McpTransport.http) {
          body['url'] = _urlController.text.trim();
          final headers = _collectMap(_headers, '请求头');
          if (headers != null) body['headers'] = headers;
        } else {
          body['command'] = _commandController.text.trim();
          final args = _argsController.text
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList(growable: false);
          if (args.isNotEmpty) body['args'] = args;
          final cwd = _cwdController.text.trim();
          if (cwd.isNotEmpty) body['cwd'] = cwd;
          final env = _collectMap(_envs, '环境变量');
          if (env != null) body['env'] = env;
        }
        await widget.client.upsertServer(name, body);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = mcpErrorMessage(error);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '编辑 MCP 服务' : '添加 MCP 服务')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_isEditing)
                    _SectionCard(
                      child: Row(
                        children: [
                          Icon(Icons.dns_outlined, color: colors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.existing!.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    TextFormField(
                      controller: _nameController,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: '服务名称',
                        hintText: '例如 github、filesystem（仅字母数字及 _ -）',
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return '请输入服务名称';
                        if (!mcpServerNamePattern.hasMatch(text)) {
                          return '仅支持字母、数字、下划线或连字符，1-64 位';
                        }
                        return null;
                      },
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    enabled: !_saving,
                    maxLength: 300,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '用途说明（可选）',
                      hintText: '供模型理解此 MCP 工具集用途',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _timeoutController,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '单次调用超时（秒）',
                      hintText: '1 - 600，默认 60',
                    ),
                    validator: (value) {
                      final parsed = int.tryParse(value?.trim() ?? '');
                      if (parsed == null || parsed < 1 || parsed > 600) {
                        return '请输入 1 到 600 之间的整数';
                      }
                      return null;
                    },
                  ),
                  if (_isEditing) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('重新配置连接与凭据参数'),
                      subtitle: const Text('仅修改说明或超时时保持关闭即可安全保留原密钥'),
                      value: _replaceConnection,
                      onChanged: _saving
                          ? null
                          : (val) => setState(() => _replaceConnection = val),
                    ),
                  ],
                  if (_replaceConnection) ...[
                    if (_isEditing &&
                        (widget.existing!.headerNames.isNotEmpty ||
                            widget.existing!.envKeys.isNotEmpty)) ...[
                      const SizedBox(height: 8),
                      _SectionCard(
                        color: colors.secondaryContainer.withValues(alpha: 0.45),
                        child: Text(
                          '服务端不会回传原请求头或环境变量的密钥明文。若开启此项保存，请为需要保留的键重新填写值；不保留的键可删除对应行。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SegmentedButton<McpTransport>(
                      segments: const [
                        ButtonSegment(
                          value: McpTransport.http,
                          label: Text('Streamable HTTP'),
                          icon: Icon(Icons.public_outlined),
                        ),
                        ButtonSegment(
                          value: McpTransport.stdio,
                          label: Text('本地命令 (stdio)'),
                          icon: Icon(Icons.terminal_outlined),
                        ),
                      ],
                      selected: {_transport},
                      onSelectionChanged: _saving
                          ? null
                          : (set) => setState(() => _transport = set.first),
                    ),
                    const SizedBox(height: 16),
                    if (_transport == McpTransport.http) ...[
                      TextFormField(
                        controller: _urlController,
                        enabled: !_saving,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: '服务端 URL',
                          hintText: 'https://example.com/mcp',
                        ),
                        validator: (value) {
                          if (!_replaceConnection ||
                              _transport != McpTransport.http) {
                            return null;
                          }
                          final text = value?.trim() ?? '';
                          final uri = Uri.tryParse(text);
                          if (uri == null ||
                              !(uri.isScheme('http') || uri.isScheme('https')) ||
                              uri.host.isEmpty) {
                            return '请输入有效的 http:// 或 https:// 地址';
                          }
                          if (uri.userInfo.isNotEmpty) {
                            return 'URL 中不能内嵌用户名或密码，请使用下方请求头';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _KeyValueSection(
                        title: '自定义请求头（可选）',
                        keyHint: '如 Authorization',
                        entries: _headers,
                        enabled: !_saving,
                        onAdd: () => setState(() => _headers.add(_KeyValueEntry())),
                        onRemove: (index) => setState(() {
                          _headers.removeAt(index).dispose();
                        }),
                        onToggleObscure: (index) => setState(() {
                          _headers[index].obscure = !_headers[index].obscure;
                        }),
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _commandController,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: '可执行命令',
                          hintText: '例如 npx、uvx、node',
                        ),
                        validator: (value) {
                          if (!_replaceConnection ||
                              _transport != McpTransport.stdio) {
                            return null;
                          }
                          if ((value?.trim() ?? '').isEmpty) {
                            return '请输入启动命令';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _argsController,
                        enabled: !_saving,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: '命令参数（可选，每行一个）',
                          hintText: '-y\n@modelcontextprotocol/server-filesystem\n./files',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _cwdController,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: '工作目录（可选）',
                          hintText: '相对路径基于工作区目录解析',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _KeyValueSection(
                        title: '环境变量（可选）',
                        keyHint: '如 API_TOKEN',
                        entries: _envs,
                        enabled: !_saving,
                        onAdd: () => setState(() => _envs.add(_KeyValueEntry())),
                        onRemove: (index) => setState(() {
                          _envs.removeAt(index).dispose();
                        }),
                        onToggleObscure: (index) => setState(() {
                          _envs[index].obscure = !_envs[index].obscure;
                        }),
                      ),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存配置'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyValueSection extends StatelessWidget {
  const _KeyValueSection({
    required this.title,
    required this.keyHint,
    required this.entries,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    required this.onToggleObscure,
  });

  final String title;
  final String keyHint;
  final List<_KeyValueEntry> entries;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onToggleObscure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            TextButton.icon(
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增'),
            ),
          ],
        ),
        for (var i = 0; i < entries.length; i++) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  controller: entries[i].keyController,
                  enabled: enabled,
                  decoration: InputDecoration(
                    labelText: '键名',
                    hintText: keyHint,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: TextField(
                  controller: entries[i].valueController,
                  enabled: enabled,
                  obscureText: entries[i].obscure,
                  decoration: InputDecoration(
                    labelText: '值',
                    suffixIcon: IconButton(
                      onPressed: enabled ? () => onToggleObscure(i) : null,
                      tooltip: entries[i].obscure ? '显示明文' : '隐藏明文',
                      icon: Icon(
                        entries[i].obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: enabled ? () => onRemove(i) : null,
                tooltip: '移除',
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: color ?? colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor ?? colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
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
