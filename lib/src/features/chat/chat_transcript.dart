import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/agenda_receipt.dart';
import 'agenda_receipt_card.dart';
import 'chat_controller.dart';
import 'chat_message_view.dart';

class ChatTranscript extends StatefulWidget {
  const ChatTranscript({
    super.key,
    required this.chat,
    required this.conversation,
    required this.messages,
    required this.footers,
    required this.onQuote,
    this.onOpenAgendaItem,
  });

  final ChatController chat;
  final Conversation conversation;
  final List<ChatMessage> messages;
  final List<Widget> footers;
  final VoidCallback onQuote;

  /// 打开日程里的某个事项。
  final AgendaItemOpener? onOpenAgendaItem;

  @override
  State<ChatTranscript> createState() => _ChatTranscriptState();
}

/// 聊天记录的展示项，承载普通消息或事项回执。
class _TranscriptEntry {
  const _TranscriptEntry.message(this.message) : receipt = null;

  const _TranscriptEntry.receipt(this.receipt) : message = null;

  final ChatMessage? message;
  final AgendaReceipt? receipt;

  DateTime? get sentAt => message?.sentAt?.toLocal();
}

class _ChatTranscriptState extends State<ChatTranscript> {
  final _position = PageStorageBucket();

  Future<void> _reportFeedbackResult(
    Conversation conversation,
    String id,
    Future<void> request,
  ) async {
    try {
      await request;
    } catch (_) {
      if (!mounted || !identical(widget.chat.active, conversation)) return;
      final unconfirmed =
          conversation.feedbackState(id) == FeedbackRequestState.unconfirmed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(unconfirmed ? '请在消息下方核对反馈状态' : '暂时无法更新反馈')),
      );
    }
  }

  /// 组装记录里的消息和事项回执。
  ///
  /// 历史消息上的回执和运行期间收到的同一份回执按 ID 去重，只保留一张卡片。
  List<_TranscriptEntry> _entries() {
    final entries = <_TranscriptEntry>[];
    final seen = <String>{};
    for (final message in widget.messages) {
      final receipt = message.agendaReceipt;
      if (receipt == null) {
        entries.add(_TranscriptEntry.message(message));
      } else if (seen.add(receipt.id)) {
        entries.add(_TranscriptEntry.receipt(receipt));
      }
    }
    for (final receipt in widget.conversation.liveAgendaReceipts) {
      if (seen.add(receipt.id)) {
        entries.add(_TranscriptEntry.receipt(receipt));
      }
    }
    return entries;
  }

  /// 上一条消息的时间，用于显示日期分隔。
  DateTime? _previousSentAt(List<_TranscriptEntry> entries, int position) {
    for (var index = position - 1; index >= 0; index--) {
      final sentAt = entries[index].sentAt;
      if (sentAt != null) return sentAt;
    }
    return null;
  }

  VoidCallback? _openAgendaItem(String itemId, {bool time = false}) {
    final open = widget.onOpenAgendaItem;
    if (open == null) return null;
    return () => open(itemId, time);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final conversation = widget.conversation;
    final binding = conversation.binding;
    final feedbackEnabled =
        binding != null && widget.chat.canChangeFeedback(conversation);
    final pending = conversation.submission;
    final entries = _entries();
    final footers = widget.footers;
    final footerCount = footers.length;
    return PageStorage(
      bucket: _position,
      child: entries.isEmpty && footerCount == 0
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  conversation.missing
                      ? '这条会话已不存在'
                      : conversation.revision == null
                      ? '正在读取聊天记录…'
                      : '今天想聊点什么？',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : NotificationListener<OverscrollIndicatorNotification>(
              onNotification: (notification) {
                // 聊天到边缘时直接停住，不拉伸消息；不影响内层横向滚动。
                if (notification.depth == 0) {
                  notification.disallowIndicator();
                }
                return false;
              },
              child: Align(
                alignment: Alignment.topCenter,
                child: ListView.separated(
                  key: PageStorageKey(conversation.id),
                  // 短对话从顶部开始，长对话仍以最新消息为滚动起点。
                  shrinkWrap: true,
                  // 只有内容超出视口时才接收纵向拖动，避免短对话被拉伸。
                  primary: false,
                  reverse: true,
                  // 从落点计算已识别的拖动，避免正文手势竞争吃掉起步距离。
                  dragStartBehavior: DragStartBehavior.down,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: entries.length + footerCount,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index < footerCount) {
                      return footers[index];
                    }
                    final position = entries.length - (index - footerCount) - 1;
                    final entry = entries[position];
                    final receipt = entry.receipt;
                    if (receipt != null) {
                      return AgendaReceiptCard(
                        key: ValueKey('agenda-receipt-${receipt.id}'),
                        receipt: receipt,
                        onOpen: _openAgendaItem(receipt.itemId),
                        onEditTime: _openAgendaItem(receipt.itemId, time: true),
                      );
                    }
                    final message = entry.message!;
                    final sentAt = entry.sentAt;
                    final previous = _previousSentAt(entries, position);
                    final confirmed =
                        pending == null ||
                        (message.id != pending.message.id &&
                            !pending.replies.containsKey(message.id));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (sentAt != null &&
                            !DateUtils.isSameDay(sentAt, previous))
                          _ChatDateLabel(sentAt),
                        ChatMessageView(
                          key: ValueKey(message.id),
                          message: message,
                          confirmed: confirmed,
                          feedbackState: conversation.feedbackState(message.id),
                          onQuote: confirmed && conversation.canEditDraft
                              ? () {
                                  if (widget.chat.quoteMessage(
                                    conversation,
                                    binding,
                                    message.id,
                                  )) {
                                    widget.onQuote();
                                  }
                                }
                              : null,
                          onReaction: feedbackEnabled
                              ? (reaction) => _reportFeedbackResult(
                                  conversation,
                                  message.id,
                                  widget.chat.changeReaction(
                                    conversation,
                                    binding,
                                    message.id,
                                    reaction,
                                  ),
                                )
                              : null,
                          onToggleSaved: feedbackEnabled
                              ? (saved) => _reportFeedbackResult(
                                  conversation,
                                  message.id,
                                  widget.chat.changeSaved(
                                    conversation,
                                    binding,
                                    message.id,
                                    saved,
                                  ),
                                )
                              : null,
                          onVerifyFeedback: feedbackEnabled
                              ? () => _reportFeedbackResult(
                                  conversation,
                                  message.id,
                                  widget.chat.verifyFeedback(
                                    conversation,
                                    binding,
                                    message.id,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class _ChatDateLabel extends StatelessWidget {
  const _ChatDateLabel(this.time);

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final day = DateUtils.isSameDay(time, DateTime.now())
        ? '今天'
        : localizations.formatShortDate(time);
    final clock = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: true,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: Color.alphaBlend(
              colors.surfaceContainerHigh.withValues(alpha: 0.7),
              colors.surface,
            ),
            shape: const StadiumBorder(),
            shadows: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              '$day $clock',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
