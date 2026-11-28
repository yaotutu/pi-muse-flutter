import '../../network/api.dart';
import 'mcp_models.dart';

class McpClient {
  const McpClient(this._api);

  final MuseApi _api;

  Future<McpOverview> loadOverview() async {
    final results = await Future.wait([
      _api.get('/api/mcp/servers'),
      _api.get('/api/assistant/mcp'),
    ]);
    final globalJson = results[0];
    final assistantJson = results[1];
    final servers = (globalJson['servers'] as List)
        .cast<Json>()
        .map(McpServer.fromJson)
        .toList(growable: false);
    final diagnostics = (globalJson['diagnostics'] as List? ?? const [])
        .cast<Json>()
        .map(McpDiagnostic.fromJson)
        .toList(growable: false);
    final assistantList = (assistantJson['servers'] as List).cast<Json>().map(
      McpAssistantServer.fromJson,
    );
    final assistantMap = {for (final item in assistantList) item.name: item};
    final rawOverrides =
        assistantJson['overrides'] as Map<String, dynamic>? ?? const {};
    final overrides = {
      for (final entry in rawOverrides.entries) entry.key: entry.value as bool,
    };
    return McpOverview(
      servers: servers,
      diagnostics: diagnostics,
      assistantServers: assistantMap,
      assistantOverrides: overrides,
    );
  }

  Future<McpServer> upsertServer(String name, Json body) async {
    final result = await _api.put(
      '/api/mcp/servers/${Uri.encodeComponent(name)}',
      body,
    );
    return McpServer.fromJson(result['server'] as Json);
  }

  Future<McpServer> patchServer(
    String name, {
    bool? enabled,
    String? description,
    int? timeout,
  }) async {
    final result = await _api.patch(
      '/api/mcp/servers/${Uri.encodeComponent(name)}',
      {'enabled': ?enabled, 'description': ?description, 'timeout': ?timeout},
    );
    return McpServer.fromJson(result['server'] as Json);
  }

  Future<void> deleteServer(String name) async {
    await _api.delete('/api/mcp/servers/${Uri.encodeComponent(name)}');
  }

  Future<McpServer> reconnectServer(String name) async {
    final result = await _api.post(
      '/api/mcp/servers/${Uri.encodeComponent(name)}/reconnect',
    );
    return McpServer.fromJson(result['server'] as Json);
  }

  Future<void> updateAssistantOverrides(Map<String, bool> overrides) async {
    await _api.put('/api/assistant/mcp', {'overrides': overrides});
  }
}

final mcpServerNamePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$');

String mcpErrorMessage(Object error) {
  if (error is ApiException) {
    if (error.status == 401) return '登录已失效，请重新连接服务器';
    return switch (error.code) {
      'CONFLICT' => '服务名称与现有服务冲突，请更换名称',
      'INVALID_INPUT' => '填写的参数格式有误，请检查后重试',
      'NOT_FOUND' => '该 MCP 服务已不存在',
      'CONFIG_CORRUPT' => '服务端 MCP 配置文件异常，请检查实例目录',
      _ => switch (error.status) {
        408 => '连接超时，请稍后重试',
        0 => '无法连接到服务器',
        _ => '操作失败，请重试',
      },
    };
  }
  return '操作失败，请重试';
}
