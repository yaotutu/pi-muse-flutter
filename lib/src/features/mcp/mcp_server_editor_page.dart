import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'mcp_client.dart';
import 'mcp_models.dart';
import 'mcp_section_card.dart';

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

class McpServerEditorPage extends StatefulWidget {
  const McpServerEditorPage({super.key, required this.client, this.existing});

  final McpClient client;
  final McpServer? existing;

  @override
  State<McpServerEditorPage> createState() => McpServerEditorPageState();
}

class McpServerEditorPageState extends State<McpServerEditorPage> {
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

  Map<String, String>? _collectMap(List<_KeyValueEntry> entries, String label) {
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
                    McpSectionCard(
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
                      McpSectionCard(
                        color: colors.secondaryContainer.withValues(
                          alpha: 0.45,
                        ),
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
                              !(uri.isScheme('http') ||
                                  uri.isScheme('https')) ||
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
                        onAdd: () =>
                            setState(() => _headers.add(_KeyValueEntry())),
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
                          hintText:
                              '-y\n@modelcontextprotocol/server-filesystem\n./files',
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
                        onAdd: () =>
                            setState(() => _envs.add(_KeyValueEntry())),
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
