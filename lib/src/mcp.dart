import 'api.dart';

enum McpTransport {
  stdio,
  http;

  static McpTransport parse(Object? raw) => switch (raw) {
    'stdio' => McpTransport.stdio,
    'http' => McpTransport.http,
    _ => throw const FormatException('Invalid MCP transport'),
  };

  String get label => switch (this) {
    McpTransport.stdio => 'STDIO',
    McpTransport.http => 'HTTP',
  };
}

enum McpConnectionStatus {
  disabled,
  disconnected,
  connecting,
  connected,
  error;

  static McpConnectionStatus parse(Object? raw) => switch (raw) {
    'disabled' => McpConnectionStatus.disabled,
    'disconnected' => McpConnectionStatus.disconnected,
    'connecting' => McpConnectionStatus.connecting,
    'connected' => McpConnectionStatus.connected,
    'error' => McpConnectionStatus.error,
    _ => throw const FormatException('Invalid MCP status'),
  };

  String get label => switch (this) {
    McpConnectionStatus.disabled => '已禁用',
    McpConnectionStatus.disconnected => '未连接',
    McpConnectionStatus.connecting => '连接中',
    McpConnectionStatus.connected => '已连接',
    McpConnectionStatus.error => '连接失败',
  };
}

class McpToolInfo {
  const McpToolInfo({
    required this.name,
    required this.exposedName,
    required this.description,
  });

  final String name;
  final String exposedName;
  final String description;

  factory McpToolInfo.fromJson(Json json) => McpToolInfo(
    name: json['name'] as String,
    exposedName: json['exposedName'] as String,
    description: json['description'] as String? ?? '',
  );
}

class McpServer {
  const McpServer({
    required this.name,
    required this.transport,
    required this.enabled,
    required this.description,
    required this.timeout,
    required this.status,
    required this.error,
    required this.connectedAt,
    required this.toolCount,
    required this.tools,
    required this.command,
    required this.args,
    required this.cwd,
    required this.envKeys,
    required this.url,
    required this.headerNames,
  });

  final String name;
  final McpTransport transport;
  final bool enabled;
  final String description;
  final int timeout;
  final McpConnectionStatus status;
  final String? error;
  final String? connectedAt;
  final int toolCount;
  final List<McpToolInfo> tools;
  final String? command;
  final List<String> args;
  final String? cwd;
  final List<String> envKeys;
  final String? url;
  final List<String> headerNames;

  factory McpServer.fromJson(Json json) => McpServer(
    name: json['name'] as String,
    transport: McpTransport.parse(json['transport']),
    enabled: json['enabled'] as bool,
    description: json['description'] as String? ?? '',
    timeout: json['timeout'] as int,
    status: McpConnectionStatus.parse(json['status']),
    error: json['error'] as String?,
    connectedAt: json['connectedAt'] as String?,
    toolCount: json['toolCount'] as int,
    tools: (json['tools'] as List? ?? const [])
        .cast<Json>()
        .map(McpToolInfo.fromJson)
        .toList(growable: false),
    command: json['command'] as String?,
    args: (json['args'] as List? ?? const []).cast<String>().toList(growable: false),
    cwd: json['cwd'] as String?,
    envKeys: (json['envKeys'] as List? ?? const [])
        .cast<String>()
        .toList(growable: false),
    url: json['url'] as String?,
    headerNames: (json['headerNames'] as List? ?? const [])
        .cast<String>()
        .toList(growable: false),
  );
}

class McpDiagnostic {
  const McpDiagnostic({required this.server, required this.message});

  final String server;
  final String message;

  factory McpDiagnostic.fromJson(Json json) => McpDiagnostic(
    server: json['server'] as String,
    message: json['message'] as String,
  );
}

class McpAssistantServer {
  const McpAssistantServer({
    required this.name,
    required this.transport,
    required this.description,
    required this.globalEnabled,
    required this.status,
    required this.toolCount,
    required this.enabled,
    required this.effectiveEnabled,
  });

  final String name;
  final McpTransport transport;
  final String description;
  final bool globalEnabled;
  final McpConnectionStatus status;
  final int toolCount;
  final bool enabled;
  final bool effectiveEnabled;

  factory McpAssistantServer.fromJson(Json json) => McpAssistantServer(
    name: json['name'] as String,
    transport: McpTransport.parse(json['transport']),
    description: json['description'] as String? ?? '',
    globalEnabled: json['globalEnabled'] as bool,
    status: McpConnectionStatus.parse(json['status']),
    toolCount: json['toolCount'] as int,
    enabled: json['enabled'] as bool,
    effectiveEnabled: json['effectiveEnabled'] as bool,
  );
}

class McpOverview {
  const McpOverview({
    required this.servers,
    required this.diagnostics,
    required this.assistantServers,
    required this.assistantOverrides,
  });

  final List<McpServer> servers;
  final List<McpDiagnostic> diagnostics;
  final Map<String, McpAssistantServer> assistantServers;
  final Map<String, bool> assistantOverrides;
}

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
    final assistantList = (assistantJson['servers'] as List)
        .cast<Json>()
        .map(McpAssistantServer.fromJson);
    final assistantMap = {
      for (final item in assistantList) item.name: item,
    };
    final rawOverrides = assistantJson['overrides'] as Map<String, dynamic>? ?? const {};
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
      {
        'enabled': ?enabled,
        'description': ?description,
        'timeout': ?timeout,
      },
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
