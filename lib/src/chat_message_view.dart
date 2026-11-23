import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

import 'chat.dart';
import 'chat_attachment_view.dart';

class ChatMessageView extends StatelessWidget {
  const ChatMessageView({
    super.key,
    required this.message,
    this.confirmed = true,
    this.onQuote,
    this.onReaction,
    this.onToggleSaved,
    this.onVerifyFeedback,
    this.feedbackState,
  });

  final ChatMessage message;

  // 已确认的消息已存在于服务端历史。发送标记只表示已发送。
  final bool confirmed;
  final VoidCallback? onQuote;
  final ValueChanged<MessageReaction>? onReaction;
  final ValueChanged<bool>? onToggleSaved;
  final VoidCallback? onVerifyFeedback;
  final FeedbackRequestState? feedbackState;

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('已复制')));
    }
  }

  List<Widget> _actions(BuildContext context, String text, bool hasText) {
    if (!confirmed) return const [];
    final colors = Theme.of(context).colorScheme;
    final canChangeFeedback = feedbackState == null;
    final onReaction = this.onReaction;
    final onToggleSaved = this.onToggleSaved;
    final liked = message.reaction == MessageReaction.like;
    final disliked = message.reaction == MessageReaction.dislike;
    return [
      if (hasText)
        IconButton(
          tooltip: '复制',
          color: colors.onSurfaceVariant,
          icon: const Icon(Icons.content_copy_outlined, size: 18),
          onPressed: () => _copy(context, text),
        ),
      if (message.canQuote)
        IconButton(
          tooltip: '引用回复',
          color: colors.onSurfaceVariant,
          icon: const Icon(Icons.format_quote_outlined, size: 20),
          onPressed: onQuote,
        ),
      if (message.feedbackAvailable) ...[
        IconButton(
          tooltip: liked ? '撤销点赞' : '点赞',
          isSelected: liked,
          color: liked ? colors.primary : colors.onSurfaceVariant,
          icon: const Icon(Icons.thumb_up_outlined, size: 18),
          selectedIcon: const Icon(Icons.thumb_up, size: 18),
          onPressed: canChangeFeedback && onReaction != null
              ? () => onReaction(MessageReaction.like)
              : null,
        ),
        IconButton(
          tooltip: disliked ? '撤销不喜欢' : '不喜欢',
          isSelected: disliked,
          color: disliked ? colors.primary : colors.onSurfaceVariant,
          icon: const Icon(Icons.thumb_down_outlined, size: 18),
          selectedIcon: const Icon(Icons.thumb_down, size: 18),
          onPressed: canChangeFeedback && onReaction != null
              ? () => onReaction(MessageReaction.dislike)
              : null,
        ),
        IconButton(
          tooltip: message.saved ? '取消收藏' : '收藏',
          isSelected: message.saved,
          color: message.saved ? colors.primary : colors.onSurfaceVariant,
          icon: const Icon(Icons.bookmark_border, size: 18),
          selectedIcon: const Icon(Icons.bookmark, size: 18),
          onPressed: canChangeFeedback && onToggleSaved != null
              ? () => onToggleSaved(!message.saved)
              : null,
        ),
        if (feedbackState == FeedbackRequestState.unconfirmed)
          IconButton(
            tooltip: '核对反馈状态',
            color: colors.onSurfaceVariant,
            icon: const Icon(Icons.sync, size: 20),
            onPressed: onVerifyFeedback,
          ),
        if (feedbackState == FeedbackRequestState.busy)
          Semantics(
            label: '正在处理反馈',
            liveRegion: true,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = message.role == 'user';
    final text = message.visibleText;
    final hasText = text.trim().isNotEmpty;
    final hasContent = hasText || message.attachments.isNotEmpty;
    // 只有工具调用的历史消息也可能允许反馈。
    if (!hasContent && (!confirmed || !message.feedbackAvailable)) {
      return const SizedBox.shrink();
    }
    final actions = _actions(context, text, hasText);

    final sentAt = message.sentAt?.toLocal();
    final time = sentAt == null
        ? null
        : Text(
            MaterialLocalizations.of(context).formatTimeOfDay(
              TimeOfDay.fromDateTime(sentAt),
              alwaysUse24HourFormat: true,
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.outline,
              letterSpacing: 0,
            ),
          );
    if (user) {
      return Padding(
        padding: const EdgeInsets.only(left: 32),
        child: FractionallySizedBox(
          widthFactor: 0.88,
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasText)
                        SelectableText(
                          text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontSize: 15,
                            height: 1.625,
                            letterSpacing: 0,
                          ),
                        )
                      else if (!hasContent)
                        const Text('无可显示的正文'),
                      if (hasText && message.attachments.isNotEmpty)
                        const SizedBox(height: 8),
                      for (final (index, attachment)
                          in message.attachments.indexed) ...[
                        if (index > 0) const SizedBox(height: 6),
                        ChatAttachmentTile(
                          key: ValueKey(attachment.id),
                          attachment: attachment,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (time != null || confirmed)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ?time,
                          if (confirmed) ...[
                            if (time != null) const SizedBox(width: 4),
                            Tooltip(
                              message: '已发送',
                              child: Icon(
                                Icons.done_all,
                                size: 14,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      ...actions,
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final body = theme.textTheme.bodyLarge!.copyWith(
      color: colors.onSurface,
      fontSize: 17,
      height: 1.75,
      letterSpacing: 0,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final replyStyles = _replyStyles(body, colors, textScaler);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.05),
            blurRadius: 20,
            spreadRadius: -4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MarkdownBody(
            data: hasText ? text : '无可显示的正文',
            fitContent: false,
            selectable: true,
            // 保留回复原文的单换行。Markdown 图片只展示替代文本。
            softLineBreak: true,
            blockSyntaxes: const [_ChatHeadingSyntax()],
            imageBuilder: (_, _, alt) => Text(alt ?? '', style: body),
            builders: {
              'chat-heading-accent': _ChatHeadingAccentBuilder(),
              'pre': _ChatCodeBlockBuilder(),
            },
            styleSheet: replyStyles,
            bulletBuilder: (bullet) =>
                _buildListMarker(bullet, replyStyles, textScaler),
          ),
          if (time != null || actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: colors.surfaceContainerLow),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ?time,
                  if (actions.isNotEmpty)
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
                    ),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _ChatHeadingSyntax extends md.HeaderSyntax {
  const _ChatHeadingSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    final node = super.parse(parser);
    // 模型有时把整段写在同一行 ## 标题里；仅改变渲染节点，保留行内强调和原始消息。
    if (node is md.Element) {
      if (node.textContent.runes.length > 56) {
        return md.Element('p', node.children);
      }
      if (const {'h1', 'h2', 'h3'}.contains(node.tag)) {
        node.children!.insert(0, md.Element.empty('chat-heading-accent'));
      }
    }
    return node;
  }
}

class _ChatHeadingAccentBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Container(
                width: 6,
                height: 16,
                decoration: ShapeDecoration(
                  color: colors.tertiary,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final codeClass = element.children
        ?.whereType<md.Element>()
        .firstOrNull
        ?.attributes['class'];
    const languagePrefix = 'language-';
    final language = codeClass != null && codeClass.startsWith(languagePrefix)
        ? codeClass.substring(languagePrefix.length)
        : '';
    final source = element.textContent;
    // 解析器为代码追加换行，保留用户在代码块内留下的其它换行和缩进。
    final code = source.endsWith('\n')
        ? source.substring(0, source.length - 1)
        : source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (language.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Text(
              language,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            code,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurface,
              fontSize: 13,
              height: 1.6,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

// 编号栏对齐到三位数；更长的编号单独缩放，避免撑宽每一级列表。
const _listMarkerSample = '888.';

double _listMarkerWidth(String marker, TextStyle style, TextScaler scaler) =>
    TextPainter.computeWidth(
      text: TextSpan(text: marker, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    );

Widget _buildListMarker(
  MarkdownBulletParameters bullet,
  MarkdownStyleSheet styles,
  TextScaler scaler,
) {
  final style = styles.listBullet!;
  if (bullet.style == BulletStyle.unorderedList) {
    return Text('•', style: style, textAlign: TextAlign.center);
  }
  final marker = '${bullet.index + 1}.';
  if (marker.length > _listMarkerSample.length) {
    final ratio =
        (styles.listIndent! - 1) / _listMarkerWidth(marker, style, scaler);
    if (ratio < 1) {
      final size = style.fontSize!;
      scaler = TextScaler.linear(scaler.scale(size) / size * ratio);
    }
  }
  return Text(
    marker,
    style: style,
    textAlign: TextAlign.right,
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    softWrap: false,
    maxLines: 1,
  );
}

MarkdownStyleSheet _replyStyles(
  TextStyle body,
  ColorScheme colors,
  TextScaler textScaler,
) {
  final heading = body.copyWith(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 26 / 18,
  );
  final listText = body.copyWith(
    color: colors.onSurfaceVariant,
    fontSize: 15,
    height: 1.625,
  );
  final subheading = listText.copyWith(
    color: colors.onSurface,
    fontWeight: FontWeight.w600,
  );
  final listBullet = listText.copyWith(
    color: colors.primary,
    fontWeight: FontWeight.w700,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  const headingInset = EdgeInsets.only(top: 8);
  return MarkdownStyleSheet(
    p: body,
    h1: heading,
    h2: heading,
    h3: heading,
    h4: subheading,
    h5: subheading,
    h6: subheading,
    h1Padding: headingInset,
    h2Padding: headingInset,
    h3Padding: headingInset,
    strong: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
    blockSpacing: 16,
    listIndent: _listMarkerWidth(
      _listMarkerSample,
      listBullet,
      textScaler,
    ).ceilToDouble(),
    listBulletPadding: const EdgeInsets.only(right: 6),
    listBullet: listBullet,
    a: TextStyle(color: colors.primary, decoration: TextDecoration.underline),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.outlineVariant)),
    ),
    blockquote: body.copyWith(
      color: colors.onSurfaceVariant,
      fontSize: 15,
      fontStyle: FontStyle.italic,
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(17, 6, 12, 6),
    blockquoteDecoration: BoxDecoration(
      color: colors.surfaceContainerLow,
      border: Border(left: BorderSide(width: 4, color: colors.tertiary)),
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
    ),
    code: TextStyle(
      fontSize: 13,
      fontFamily: 'monospace',
      color: colors.primary,
      backgroundColor: colors.surfaceContainerLow,
    ),
    codeblockDecoration: BoxDecoration(
      color: colors.surfaceContainerLow,
      border: Border.all(color: colors.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
  );
}
