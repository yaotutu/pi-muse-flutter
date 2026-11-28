import '../../network/api.dart';

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
    args: (json['args'] as List? ?? const []).cast<String>().toList(
      growable: false,
    ),
    cwd: json['cwd'] as String?,
    envKeys: (json['envKeys'] as List? ?? const []).cast<String>().toList(
      growable: false,
    ),
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
