import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as flutter;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/main.dart';
import 'package:pi_muse_flutter/src/chat.dart';
import 'package:pi_muse_flutter/src/chat_message_view.dart';

void main() {
  testWidgets(
    'narrow chat keeps headings close to body type at large text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const markdown =
          '## 雨天备选：如果天气一直不好，就把行程放在室内。\n\n'
          '这里是一段正常正文，包含 **重点** 和 `inline code`。\n\n'
          '- 先找附近的展馆\n- 预留喝杯咖啡的时间\n\n'
          '> 验收示例引用。\n\n---\n\n![示例图片](https://example.invalid/image.png)';
      await tester.pumpWidget(
        MaterialApp(
          theme: museTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ChatMessageView(
                message: ChatMessage('reply', 'assistant', markdown),
              ),
            ),
          ),
        ),
      );
      final reply = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      final style = reply.styleSheet!;
      for (final heading in [
        style.h1!,
        style.h2!,
        style.h3!,
        style.h4!,
        style.h5!,
        style.h6!,
      ]) {
        expect(heading.fontSize! - style.p!.fontSize!, lessThanOrEqualTo(2));
      }
      final colors = museTheme(Brightness.light).colorScheme;
      expect(style.p!.height, 1.75);
      expect(style.strong!.color, colors.primary);
      expect(style.code!.backgroundColor, colors.surfaceContainerLow);
      expect(
        (style.blockquoteDecoration! as BoxDecoration).border,
        Border(left: BorderSide(width: 4, color: colors.tertiary)),
      );
      expect(reply.selectable, isTrue);
      expect(find.text('示例图片'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('assistant line breaks survive rendering beside bold text', (
    tester,
  ) async {
    const title = '09:00–10:45 浙江省博物馆孤山馆区';
    const description = '主馆是「中国通史」。';
    const reply =
        '**$title**\n$description\n\n'
        '**11:45–13:00 午饭**\n楼外楼就在公园边。';
    await tester.pumpWidget(
      MaterialApp(
        theme: museTheme(Brightness.light),
        home: const Scaffold(
          body: ChatMessageView(
            message: ChatMessage('reply', 'assistant', reply),
          ),
        ),
      ),
    );
    final markdown = find.byType(MarkdownBody);
    final blocks = tester
        .widgetList<flutter.EditableText>(
          find.descendant(
            of: markdown,
            matching: find.byType(flutter.EditableText),
          ),
        )
        .map((block) => block.controller.text);
    expect(blocks, contains('$title\n$description'));
    expect(blocks, contains('11:45–13:00 午饭\n楼外楼就在公园边。'));
    expect(tester.widget<MarkdownBody>(markdown).data, reply);
  });

  testWidgets('paragraph-sized headings keep their inline meaning', (
    tester,
  ) async {
    const longLine =
        '下雨时就把路线上比较分散的景点换成同一片区的展馆，'
        '这样不用反复换车，也有时间坐下来歇一会儿。别忘了保留 **午饭时间**。';
    const text = '## 雨天路线\n\n## $longLine\n\n```text\n## $longLine\n```';
    await tester.pumpWidget(
      MaterialApp(
        theme: museTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ChatMessageView(
              message: ChatMessage('reply', 'assistant', text),
            ),
          ),
        ),
      ),
    );
    final reply = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(reply.data, text);
    final rendered = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      blockSyntaxes: reply.blockSyntaxes,
    ).parseLines(text.split('\n')).cast<md.Element>();
    expect(rendered.map((node) => node.tag), ['h2', 'p', 'pre']);
    expect(rendered[1].children!.whereType<md.Element>().single.tag, 'strong');
    expect(rendered[2].textContent, contains('## $longLine'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('user bubble aligns right and checks only confirmed sends', (
    tester,
  ) async {
    final message = ChatMessage(
      'user-1',
      'user',
      '你好',
      sentAt: DateTime(2026, 11, 23, 10, 15),
    );
    final theme = museTheme(Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              ChatMessageView(message: message, confirmed: false),
              ChatMessageView(message: message),
            ],
          ),
        ),
      ),
    );

    final bubbles = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color ==
              theme.colorScheme.primaryContainer,
    );
    expect(bubbles, findsNWidgets(2));
    final box = tester.getRect(find.byType(ChatMessageView).first);
    final bubble = tester.getRect(bubbles.first);
    expect(bubble.right, box.right);
    expect(bubble.width, lessThan(box.width));
    expect(find.text('10:15'), findsNWidgets(2));
    expect(find.byTooltip('已发送'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatMessageView).first,
        matching: find.byIcon(Icons.done_all),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'code panels use fence languages and preserve code on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const code =
          'void main() {\n'
          '  final description = "A line long enough to scroll horizontally in the reply card.";\n'
          '\n'
          '}';
      const reply =
          '```dart\n$code\n```\n\n'
          '~~~json\n{"ok": true}\n~~~\n\n'
          '```\nplain code\n```';
      await tester.pumpWidget(
        MaterialApp(
          theme: museTheme(Brightness.light),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ChatMessageView(
                message: ChatMessage('reply', 'assistant', reply),
              ),
            ),
          ),
        ),
      );

      expect(find.text('dart'), findsOneWidget);
      expect(find.text('json'), findsOneWidget);
      expect(find.text('text'), findsNothing);
      expect(find.text(code), findsOneWidget);
      final scroll = tester.state<flutter.ScrollableState>(
        find.ancestor(
          of: find.text(code),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is flutter.Scrollable &&
                widget.axisDirection == AxisDirection.right,
          ),
        ),
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('assistant footer copies the visible source once confirmed', (
    tester,
  ) async {
    const text = '**可见内容**\n下一行';
    const source = '<think>内部推理</think>\n\n$text';
    const streaming = ChatMessage('reply', 'assistant', source);
    final saved = ChatMessage(
      'reply',
      'assistant',
      source,
      sentAt: DateTime(2026, 11, 23, 10, 16),
    );
    final clipboardCalls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: museTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              const ChatMessageView(message: streaming, confirmed: false),
              ChatMessageView(message: saved),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Pi Muse'), findsNothing);
    expect(find.text('10:16'), findsOneWidget);
    expect(find.byTooltip('复制'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatMessageView).first,
        matching: find.byTooltip('复制'),
      ),
      findsNothing,
    );
    await tester.tap(find.byTooltip('复制'));
    await tester.pumpAndSettle();
    expect(clipboardCalls.single.arguments, {'text': text});
    expect(find.text('已复制'), findsOneWidget);
  });

  test('chat text and action colors have readable contrast in both themes', () {
    double contrast(Color first, Color second) {
      final a = first.computeLuminance();
      final b = second.computeLuminance();
      return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
    }

    for (final brightness in Brightness.values) {
      final colors = museTheme(brightness).colorScheme;
      for (final (text, surface) in [
        (colors.onSurface, colors.surface),
        (colors.onSurface, colors.surfaceContainerLow),
        (colors.onSurfaceVariant, colors.surfaceContainerLow),
        (colors.onPrimaryContainer, colors.primaryContainer),
        (colors.primary, colors.surfaceContainerLow),
        (colors.tertiary, colors.surfaceContainerLow),
        (colors.onTertiaryContainer, colors.tertiaryContainer),
        (colors.onPrimary, colors.primary),
      ]) {
        expect(contrast(text, surface), greaterThanOrEqualTo(4.5));
      }
    }
  });
}
