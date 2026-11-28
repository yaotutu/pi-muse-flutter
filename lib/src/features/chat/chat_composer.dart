import 'package:material_ui/material_ui.dart';

import 'chat_controller.dart';
import 'chat_attachment_view.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.chat,
    required this.conversation,
    required this.focus,
    required this.controller,
    required this.compact,
    required this.running,
    required this.localRunning,
  });

  final ChatController chat;
  final Conversation conversation;
  final FocusNode focus;
  final TextEditingController controller;
  final bool compact;
  final bool running;
  final bool localRunning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (conversation.hasRecoveredDraft)
          TextButton(
            onPressed: conversation.canEditDraft && !chat.pickingAttachments
                ? chat.recoverDraft
                : null,
            child: const Text('切换未发送草稿'),
          ),
        if (conversation.quote case final MessageQuote quote)
          _QuotePreview(
            quote: quote,
            onRemove: conversation.canEditDraft ? chat.removeQuote : null,
          ),
        if (conversation.draftAttachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: SingleChildScrollView(
              key: PageStorageKey('attachments-${conversation.id}'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final attachment in conversation.draftAttachments)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 210,
                        child: ChatAttachmentTile(
                          key: ValueKey(attachment.id),
                          attachment: attachment,
                          onRemove:
                              chat.pickingAttachments ||
                                  !conversation.canEditDraft
                              ? null
                              : () => chat.removeDraftAttachment(attachment.id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: ListenableBuilder(
            listenable: focus,
            builder: (context, child) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: colors.tertiary.withValues(alpha: 0.07),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: colors.surfaceContainerLowest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                  side: focus.hasFocus
                      ? BorderSide(color: colors.primary)
                      : BorderSide.none,
                ),
                child: child,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: chat.pickingAttachments ? '正在读取附件' : '添加附件',
                    onPressed: chat.canPickAttachments
                        ? () {
                            focus.unfocus();
                            chat.chooseAttachments();
                          }
                        : null,
                    icon: chat.pickingAttachments
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.attach_file,
                            size: 22,
                            color: colors.outline,
                          ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      readOnly: !conversation.canEditDraft,
                      onChanged: chat.setDraft,
                      minLines: 1,
                      maxLines: compact ? 3 : 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 15,
                        letterSpacing: 0,
                      ),
                      decoration: InputDecoration(
                        hintText: '发消息给 Pi Muse',
                        hintStyle: TextStyle(color: colors.outline),
                        filled: false,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ValueListenableBuilder(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final hasContent =
                          value.text.trim().isNotEmpty ||
                          conversation.draftAttachments.isNotEmpty;
                      final waiting = conversation.waitingToSend;
                      final action = running
                          ? chat.canStop(sendNext: hasContent)
                                ? hasContent
                                      ? chat.stopAndSend
                                      : chat.stop
                                : null
                          : chat.canSend && hasContent
                          ? chat.send
                          : null;
                      final label = waiting
                          ? '正在停止并准备发送'
                          : running
                          ? hasContent
                                ? localRunning
                                      ? '停止并发送'
                                      : '请先停止或等待当前回复完成'
                                : '停止回复'
                          : '发送';
                      return IconButton(
                        key: ValueKey(running || waiting ? 'stop' : 'send'),
                        tooltip: label,
                        onPressed: action,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        icon: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: action == null
                                ? colors.surfaceContainerHigh
                                : colors.tertiary,
                          ),
                          child: SizedBox.square(
                            dimension: 36,
                            child: Icon(
                              running || waiting
                                  ? hasContent
                                        ? Icons.send_outlined
                                        : Icons.stop_rounded
                                  : Icons.arrow_upward_rounded,
                              color: action == null
                                  ? colors.outline
                                  : colors.onTertiary,
                              size: 20,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuotePreview extends StatelessWidget {
  const _QuotePreview({required this.quote, required this.onRemove});

  final MessageQuote quote;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 12,
            top: 4,
            bottom: 4,
          ),
          child: Row(
            children: [
              Icon(
                Icons.format_quote_outlined,
                color: colors.onSecondaryContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quote.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                    Text(
                      quote.excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '移除引用',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
