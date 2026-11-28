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
            builder: (context, child) => Material(
              color: colors.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: focus.hasFocus
                    ? BorderSide(color: colors.primary, width: 2)
                    : BorderSide.none,
              ),
              child: child,
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
                        : const Icon(Icons.attach_file),
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
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: '发消息给 Pi Muse',
                        hintStyle: TextStyle(color: colors.onSurfaceVariant),
                        filled: false,
                        border: InputBorder.none,
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
                      final stopping =
                          conversation.submission?.stopping == true ||
                          conversation.stoppingActiveRun;
                      final busy = waiting || stopping;
                      // 其他设备发起的运行不能自动接发本机草稿；仍可单独停止。
                      final sendNext =
                          localRunning &&
                          hasContent &&
                          chat.canStop(sendNext: true);
                      final (label, icon, action) = switch ((
                        waiting,
                        stopping,
                        running,
                      )) {
                        (true, _, _) => ('正在停止并准备发送', Icons.sync, null),
                        (_, true, _) => ('正在停止回复', Icons.sync, null),
                        (_, _, true) when sendNext => (
                          '停止并发送',
                          Icons.send_outlined,
                          chat.stopAndSend,
                        ),
                        (_, _, true) => (
                          '停止回复',
                          Icons.stop_rounded,
                          chat.canStop(sendNext: false) ? chat.stop : null,
                        ),
                        _ => (
                          '发送',
                          Icons.arrow_upward_rounded,
                          hasContent && chat.canSend ? chat.send : null,
                        ),
                      };
                      return IconButtonTheme(
                        data: const IconButtonThemeData(
                          variant: StyleVariant.material3Expressive,
                        ),
                        child: IconButton.filled(
                          key: ValueKey(running || busy ? 'stop' : 'send'),
                          tooltip: label,
                          onPressed: action,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.padded,
                            visualDensity: VisualDensity.standard,
                          ),
                          icon: Icon(icon),
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
