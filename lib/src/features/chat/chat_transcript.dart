import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

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
  });

  final ChatController chat;
  final Conversation conversation;
  final List<ChatMessage> messages;
  final List<Widget> footers;
  final VoidCallback onQuote;

  @override
  State<ChatTranscript> createState() => _ChatTranscriptState();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final conversation = widget.conversation;
    final binding = conversation.binding;
    final feedbackEnabled =
        binding != null && widget.chat.canChangeFeedback(conversation);
    final pending = conversation.submission;
    final messages = widget.messages;
    final footers = widget.footers;
    final footerCount = footers.length;
    return PageStorage(
      bucket: _position,
      child: messages.isEmpty && footerCount == 0
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
                  itemCount: messages.length + footerCount,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index < footerCount) {
                      return footers[index];
                    }
                    final position =
                        messages.length - (index - footerCount) - 1;
                    final message = messages[position];
                    final sentAt = message.sentAt?.toLocal();
                    final previous = position == 0
                        ? null
                        : messages[position - 1].sentAt?.toLocal();
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
