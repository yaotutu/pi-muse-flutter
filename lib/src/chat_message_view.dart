import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

import 'chat.dart';
import 'visible_text.dart';

class ChatMessageView extends StatelessWidget {
  const ChatMessageView({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = message.role == 'user';
    final text = user ? message.text : visibleAssistantText(message.text);
    if (text.trim().isEmpty) return const SizedBox.shrink();

    final body = theme.textTheme.bodyLarge!.copyWith(
      color: colors.onSurface,
      height: 1.5,
    );
    if (user) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: FractionallySizedBox(
          widthFactor: 0.86,
          alignment: Alignment.centerRight,
          child: Align(
            alignment: Alignment.centerRight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 10,
                ),
                child: SelectableText(
                  text,
                  style: body.copyWith(color: colors.onPrimaryContainer),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.tertiaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: 26,
                    child: Icon(
                      Icons.auto_awesome_outlined,
                      size: 15,
                      color: colors.onTertiaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Pi Muse',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          MarkdownBody(
            data: text,
            selectable: true,
            blockSyntaxes: const [_ChatHeadingSyntax()],
            imageBuilder: (_, _, alt) => Text(alt ?? ''),
            styleSheet: _replyStyles(body, colors),
          ),
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
    if (node is md.Element && node.textContent.runes.length > 56) {
      return md.Element('p', node.children);
    }
    return node;
  }
}

MarkdownStyleSheet _replyStyles(TextStyle body, ColorScheme colors) {
  final heading = body.copyWith(fontWeight: FontWeight.w600);
  const headingInset = EdgeInsets.only(top: 3);
  return MarkdownStyleSheet(
    p: body,
    h1: heading.copyWith(fontSize: 18, height: 1.38),
    h2: heading.copyWith(fontSize: 17, height: 1.44),
    h3: heading,
    h4: heading,
    h5: heading,
    h6: heading,
    h1Padding: headingInset,
    h2Padding: headingInset,
    h3Padding: headingInset,
    strong: const TextStyle(fontWeight: FontWeight.w600),
    blockSpacing: 10,
    listIndent: 17,
    listBulletPadding: const EdgeInsets.only(right: 4),
    listBullet: body.copyWith(color: colors.tertiary),
    a: TextStyle(color: colors.primary, decoration: TextDecoration.underline),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.outlineVariant)),
    ),
    blockquote: body.copyWith(color: colors.onSurfaceVariant),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    blockquoteDecoration: BoxDecoration(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    code: body.copyWith(
      fontSize: 14,
      fontFamily: 'monospace',
      color: colors.onPrimaryContainer,
      backgroundColor: colors.surfaceContainer,
    ),
    codeblockDecoration: BoxDecoration(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    codeblockPadding: const EdgeInsets.all(12),
  );
}
