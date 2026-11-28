import 'package:material_ui/material_ui.dart';

import '../../network/api.dart';
import 'mcp_client.dart';
import 'mcp_models.dart';
import 'mcp_server_card.dart';
import 'mcp_server_editor_page.dart';
import 'mcp_section_card.dart';

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
            McpServerEditorPage(client: _client, existing: existing),
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
              FilledButton(onPressed: () => _reload(), child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final overview = _overview!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        McpSectionCard(
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
          McpSectionCard(
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
          McpSectionCard(
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
            McpServerCard(
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
