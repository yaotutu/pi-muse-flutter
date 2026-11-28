import '../network/api.dart';

/// 事项操作回执。服务端只返回已保存结果的快照，修改时按 itemId 回读业务事实。
class AgendaReceipt {
  const AgendaReceipt({
    required this.id,
    required this.itemId,
    required this.title,
    required this.kind,
    this.when,
    this.timeZone,
  });

  /// 解析回执。字段不完整时返回 null，不影响聊天历史里的其它内容。
  static AgendaReceipt? tryParse(Object? value) {
    if (value is! Json) return null;
    final id = value['id'];
    final itemId = value['itemId'];
    final title = value['title'];
    final kind = value['kind'];
    if (id is! String ||
        itemId is! String ||
        title is! String ||
        kind is! String) {
      return null;
    }
    if (id.isEmpty || itemId.isEmpty || title.isEmpty || kind.isEmpty) {
      return null;
    }
    final when = value['when'];
    final timeZone = value['timeZone'];
    return AgendaReceipt(
      id: id,
      itemId: itemId,
      title: title,
      kind: kind,
      when: when is String && when.isNotEmpty ? when : null,
      timeZone: timeZone is String && timeZone.isNotEmpty ? timeZone : null,
    );
  }

  final String id;
  final String itemId;
  final String title;
  final String kind;
  final String? when;
  final String? timeZone;

  /// 回执类型的展示文案。
  String get label => switch (kind) {
    'item_created' => '已创建事项',
    'schedule_created' => '已安排时间',
    'reminder_created' => '已创建提醒',
    'reminder_added' => '已添加提醒',
    'item_updated' => '已更新事项',
    'item_completed' => '已完成事项',
    _ => '事项变更',
  };
}

/// 助手历史消息含同一份回执快照。
AgendaReceipt? agendaReceiptFromMessage(Json message) =>
    message['role'] == 'assistant'
    ? AgendaReceipt.tryParse(message['agendaReceipt'])
    : null;

/// AG-UI CUSTOM 事件的 value 是同一份回执对象。
AgendaReceipt? agendaReceiptFromEvent(Json event) =>
    event['type'] == 'CUSTOM' && event['name'] == 'agenda_receipt'
    ? AgendaReceipt.tryParse(event['value'])
    : null;
