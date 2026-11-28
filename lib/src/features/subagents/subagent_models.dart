import '../../network/api.dart';
import '../mcp/mcp_models.dart';

class SubagentToolSpec {
  const SubagentToolSpec({
    required this.name,
    required this.description,
    required this.triggers,
    this.requiresApproval = false,
  });

  final String name;
  final String description;
  final List<String> triggers;
  final bool requiresApproval;

  factory SubagentToolSpec.fromJson(Json json) => SubagentToolSpec(
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    triggers: (json['triggers'] as List? ?? const []).cast<String>().toList(
      growable: false,
    ),
    requiresApproval: json['requiresApproval'] as bool? ?? false,
  );
}

class SubagentMcpBinding {
  const SubagentMcpBinding({
    required this.name,
    this.description,
    this.transport,
  });

  final String name;
  final String? description;
  final String? transport;

  factory SubagentMcpBinding.fromJson(Json json) => SubagentMcpBinding(
    name: json['name'] as String,
    description: json['description'] as String?,
    transport: json['transport'] as String?,
  );
}

class SubagentPromptSection {
  const SubagentPromptSection({
    required this.key,
    required this.label,
    required this.trigger,
    required this.source,
    required this.sourcePath,
    required this.editable,
    required this.content,
  });

  final String key;
  final String label;
  final String trigger;
  final String source;
  final String sourcePath;
  final bool editable;
  final String content;

  factory SubagentPromptSection.fromJson(Json json) => SubagentPromptSection(
    key: json['key'] as String,
    label: json['label'] as String,
    trigger: json['trigger'] as String,
    source: json['source'] as String,
    sourcePath: json['sourcePath'] as String,
    editable: json['editable'] as bool,
    content: json['content'] as String,
  );
}

class SubagentIncludeDiagnostic {
  const SubagentIncludeDiagnostic({required this.path, required this.status});

  final String path;
  final String status;

  factory SubagentIncludeDiagnostic.fromJson(Json json) =>
      SubagentIncludeDiagnostic(
        path: json['path'] as String? ?? '',
        status: json['status'] as String? ?? '',
      );
}

class SubagentHabit {
  const SubagentHabit({
    required this.id,
    required this.text,
    required this.source,
  });

  final String id;
  final String text;
  final String source;

  factory SubagentHabit.fromJson(Json json) => SubagentHabit(
    id: json['id'] as String,
    text: json['text'] as String,
    source: json['source'] as String? ?? '',
  );
}

class SubagentUserInstructions {
  const SubagentUserInstructions({
    required this.path,
    required this.instructions,
    required this.includes,
    required this.habits,
    this.unconsolidatedFeedbackCount,
  });

  final String path;
  final String instructions;
  final List<SubagentIncludeDiagnostic> includes;
  final List<SubagentHabit> habits;
  final int? unconsolidatedFeedbackCount;

  factory SubagentUserInstructions.fromJson(Json json) =>
      SubagentUserInstructions(
        path: json['path'] as String,
        instructions: json['instructions'] as String? ?? '',
        includes: (json['includes'] as List? ?? const [])
            .cast<Json>()
            .map(SubagentIncludeDiagnostic.fromJson)
            .toList(growable: false),
        habits: (json['habits'] as List? ?? const [])
            .cast<Json>()
            .map(SubagentHabit.fromJson)
            .toList(growable: false),
        unconsolidatedFeedbackCount:
            json['unconsolidatedFeedbackCount'] as int?,
      );
}

class SubagentSummary {
  const SubagentSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.routingHint,
    required this.triggers,
    required this.enabled,
    required this.parallelAllowed,
    required this.hasUserInstructions,
    required this.tools,
    required this.mcp,
    required this.enabledEditable,
    required this.mcpEditable,
    required this.userInstructionsEditable,
  });

  final String id;
  final String name;
  final String description;
  final String? routingHint;
  final List<String> triggers;
  final bool enabled;
  final bool parallelAllowed;
  final bool hasUserInstructions;
  final List<SubagentToolSpec> tools;
  final List<SubagentMcpBinding> mcp;
  final bool enabledEditable;
  final bool mcpEditable;
  final bool userInstructionsEditable;

  bool get supportsChat => triggers.contains('chat');
  bool get supportsBackground => triggers.contains('background');

  factory SubagentSummary.fromJson(Json json) {
    final policy = json['executionPolicy'] as Json? ?? const {};
    final capabilities = json['capabilities'] as Json? ?? const {};
    final editability = json['editability'] as Json? ?? const {};
    return SubagentSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      routingHint: json['routingHint'] as String?,
      triggers: (json['triggers'] as List? ?? const []).cast<String>().toList(
        growable: false,
      ),
      enabled: json['enabled'] as bool? ?? true,
      parallelAllowed: policy['parallelAllowed'] as bool? ?? true,
      hasUserInstructions: json['hasUserInstructions'] as bool? ?? false,
      tools: (capabilities['tools'] as List? ?? const [])
          .cast<Json>()
          .map(SubagentToolSpec.fromJson)
          .toList(growable: false),
      mcp: (capabilities['mcp'] as List? ?? const [])
          .cast<Json>()
          .map(SubagentMcpBinding.fromJson)
          .toList(growable: false),
      enabledEditable: editability['enabled'] != 'readonly',
      mcpEditable: editability['mcp'] == 'editable',
      userInstructionsEditable: editability['userInstructions'] == 'editable',
    );
  }
}

class SubagentDetail {
  const SubagentDetail({
    required this.summary,
    required this.prompts,
    required this.userInstructions,
  });

  final SubagentSummary summary;
  final List<SubagentPromptSection> prompts;
  final SubagentUserInstructions? userInstructions;

  factory SubagentDetail.fromJson(Json json) {
    final rawInstructions = json['userInstructions'] as Json?;
    return SubagentDetail(
      summary: SubagentSummary.fromJson(json),
      prompts: (json['prompts'] as List? ?? const [])
          .cast<Json>()
          .map(SubagentPromptSection.fromJson)
          .toList(growable: false),
      userInstructions: rawInstructions == null
          ? null
          : SubagentUserInstructions.fromJson(rawInstructions),
    );
  }
}

class SubagentMcpServerOption {
  const SubagentMcpServerOption({
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

  factory SubagentMcpServerOption.fromJson(Json json) =>
      SubagentMcpServerOption(
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

class SubagentMcpSelection {
  const SubagentMcpSelection({
    required this.subagentId,
    required this.editable,
    required this.servers,
    required this.enabledServers,
  });

  final String subagentId;
  final bool editable;
  final List<SubagentMcpServerOption> servers;
  final List<String> enabledServers;

  factory SubagentMcpSelection.fromJson(Json json) => SubagentMcpSelection(
    subagentId: json['subagentId'] as String,
    editable: json['editable'] as bool,
    servers: (json['servers'] as List? ?? const [])
        .cast<Json>()
        .map(SubagentMcpServerOption.fromJson)
        .toList(growable: false),
    enabledServers: (json['enabledServers'] as List? ?? const [])
        .cast<String>()
        .toList(growable: false),
  );
}
