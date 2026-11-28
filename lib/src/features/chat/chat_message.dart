part of 'chat_controller.dart';

/// 单条消息允许的最大字符数（含引用）。
const maxChatMessageLength = 32000;

/// 用户对回复的评价。
enum MessageReaction { like, dislike }

/// 反馈请求的确认状态。
enum FeedbackRequestState { busy, unconfirmed }

MessageReaction? _readReaction(Json feedback) => switch (feedback['reaction']) {
  'like' => MessageReaction.like,
  'dislike' => MessageReaction.dislike,
  null when feedback.containsKey('reaction') => null,
  _ => throw const FormatException('Invalid message reaction'),
};

bool _readSaved(Json feedback) => switch (feedback['saved']) {
  final bool saved => saved,
  _ => throw const FormatException('Invalid message saved state'),
};

/// 一条聊天消息。
class ChatMessage {
  const ChatMessage(
    this.id,
    this.role,
    this.text, {
    this.attachments = const [],
    this.sentAt,
    this.source,
    this.runId,
    this.feedbackAvailable = false,
    this.reaction,
    this.saved = false,
    this.agendaReceipt,
  });

  factory ChatMessage.fromJson(Json json) {
    final metadata = json['metadata'] as Json?;
    final createdAt = metadata?['createdAt'];
    final feedback = json['feedback'];
    final feedbackAvailable =
        metadata?['feedbackAvailable'] == true && feedback is Json;
    return ChatMessage(
      json['id'] as String,
      json['role'] as String,
      json['content'] as String? ?? '',
      sentAt: createdAt is String ? DateTime.tryParse(createdAt) : null,
      source: metadata?['source'] as String?,
      runId: metadata?['runId'] as String?,
      feedbackAvailable: feedbackAvailable,
      reaction: feedbackAvailable ? _readReaction(feedback) : null,
      saved: feedbackAvailable && _readSaved(feedback),
      agendaReceipt: agendaReceiptFromMessage(json),
      attachments:
          (json['attachments'] as List?)
              ?.cast<Json>()
              .map(ChatAttachment.fromJson)
              .toList(growable: false) ??
          const [],
    );
  }

  final String id;
  final String role;
  final String text;
  final List<ChatAttachment> attachments;
  final DateTime? sentAt;
  final String? source;
  final String? runId;
  final bool feedbackAvailable;
  final MessageReaction? reaction;
  final bool saved;

  /// 助手消息上的事项回执。回执只是快照，修改要按 itemId 回读事项。
  final AgendaReceipt? agendaReceipt;

  String get visibleText =>
      role == 'assistant' ? visibleAssistantText(text) : text;
  bool get canQuote =>
      (source == null || source == 'chat') &&
      (role == 'user' || role == 'assistant') &&
      visibleText.trim().isNotEmpty;

  ChatMessage _withFeedback(MessageReaction? reaction, bool saved) =>
      ChatMessage(
        id,
        role,
        text,
        attachments: attachments,
        sentAt: sentAt,
        source: source,
        runId: runId,
        feedbackAvailable: feedbackAvailable,
        reaction: reaction,
        saved: saved,
      );
}

/// 被引用的消息片段。
class MessageQuote {
  MessageQuote._(ChatMessage message)
    : label = message.role == 'assistant' ? '助手回复' : '我的消息',
      excerpt = _quoteExcerpt(message.visibleText.trim());

  static String _quoteExcerpt(String text) {
    var end = 0;
    for (final character in text.characters.take(1200)) {
      if (end + character.length > 4800) break;
      end += character.length;
    }
    return end == text.length ? text : '${text.substring(0, end)}…';
  }

  final String label;
  final String excerpt;

  String compose(String text) {
    final lines = const LineSplitter().convert(excerpt);
    return '> $label\n${lines.map((line) => '> $line').join('\n')}\n\n$text';
  }
}
