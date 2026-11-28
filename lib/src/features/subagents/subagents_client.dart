import '../../network/api.dart';
import 'subagent_models.dart';

class SubagentsClient {
  const SubagentsClient(this._api);

  final MuseApi _api;

  Future<List<SubagentSummary>> list() async {
    final result = await _api.get('/api/subagents');
    return (result['subagents'] as List)
        .cast<Json>()
        .map(SubagentSummary.fromJson)
        .toList(growable: false);
  }

  Future<SubagentDetail> getDetail(String id) async {
    final result = await _api.get('/api/subagents/${Uri.encodeComponent(id)}');
    return SubagentDetail.fromJson(result);
  }

  Future<SubagentDetail> setEnabled(String id, bool enabled) async {
    final result = await _api.patch(
      '/api/subagents/${Uri.encodeComponent(id)}',
      {'enabled': enabled},
    );
    return SubagentDetail.fromJson(result);
  }

  Future<SubagentMcpSelection> getMcpSelection(String id) async {
    final result = await _api.get(
      '/api/subagents/${Uri.encodeComponent(id)}/mcp',
    );
    return SubagentMcpSelection.fromJson(result);
  }

  Future<SubagentMcpSelection> updateMcpSelection(
    String id,
    List<String> servers,
  ) async {
    final result = await _api.put(
      '/api/subagents/${Uri.encodeComponent(id)}/mcp',
      {'servers': servers},
    );
    return SubagentMcpSelection.fromJson(result);
  }

  Future<SubagentUserInstructions> updateUserInstructions(
    String id,
    String instructions,
    String existingPath,
  ) async {
    final endpoint = switch (id) {
      'sms' => '/api/information/preferences',
      'news' => '/api/news/preferences',
      _ => throw StateError('Subagent $id does not support instructions'),
    };
    final result = await _api.put(endpoint, {'instructions': instructions});
    return SubagentUserInstructions.fromJson({...result, 'path': existingPath});
  }
}

String subagentErrorMessage(Object error) {
  if (error is ApiException) {
    if (error.status == 401) return '登录已失效，请重新连接服务器';
    return switch (error.code) {
      'INVALID_INPUT' => '内容格式无效或超出长度限制',
      'NOT_FOUND' => 'Subagent 或关联服务不存在',
      'SERVICE_UNAVAILABLE' => '服务暂不可用，请稍后重试',
      _ => switch (error.status) {
        408 => '请求超时，请稍后重试',
        0 => '无法连接到服务器',
        _ => '操作失败，请重试',
      },
    };
  }
  return '操作失败，请重试';
}
