import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as flutter;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/appearance.dart';
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
          theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
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
      final colors = museTheme(
        MusePalette.indigo.colors(Brightness.light),
      ).colorScheme;
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
        theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
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

  testWidgets('long pressing assistant text opens its localized toolbar', (
    tester,
  ) async {
    const reply = 'Select this reply';
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: [Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: ChatMessageView(
            message: ChatMessage('reply', 'assistant', reply),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text(reply));
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('ordered list numbers stay on one line at large text sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const reply =
        '9. First\n10. Second\n\n'
        'A separate list.\n\n'
        '99. Third\n100. Fourth\n   - Nested bullet\n\n'
        'A list with a large starting number.\n\n'
        '999999999. Last';

    for (final scaler in [TextScaler.noScaling, TextScaler.linear(2)]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ChatMessageView(
                message: ChatMessage('reply', 'assistant', reply),
              ),
            ),
          ),
        ),
      );

      for (final number in ['9.', '10.', '99.', '100.', '999999999.']) {
        final marker = find.text(number);
        expect(marker, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: marker, matching: find.byType(flutter.RichText)),
        );
        final boxes = paragraph.getBoxesForSelection(
          flutter.TextSelection(baseOffset: 0, extentOffset: number.length),
        );
        expect(boxes, hasLength(1), reason: '$number wraps at $scaler');
        expect(boxes.single.right, lessThanOrEqualTo(paragraph.size.width));
      }
      expect(
        tester.getTopLeft(find.text('First')).dx,
        tester.getTopLeft(find.text('Fourth')).dx,
      );
      expect(find.text('•'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
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
        theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
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
    final theme = museTheme(MusePalette.indigo.colors(Brightness.light));
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
          theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
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
        theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
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

  testWidgets('inline feedback verification fits a narrow message footer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ChatMessageView(
              message: ChatMessage(
                'question',
                'user',
                '测试消息',
                sentAt: DateTime(2026, 11, 23, 10, 16),
                feedbackAvailable: true,
                reaction: MessageReaction.like,
                saved: true,
              ),
              onQuote: () {},
              feedbackState: FeedbackRequestState.unconfirmed,
              onReaction: (_) => fail('Unconfirmed feedback is locked'),
              onToggleSaved: (_) => fail('Unconfirmed feedback is locked'),
              onVerifyFeedback: () => checks++,
            ),
          ),
        ),
      ),
    );

    final like = find.widgetWithIcon(IconButton, Icons.thumb_up);
    expect(tester.widget<IconButton>(like).isSelected, true);
    expect(tester.widget<IconButton>(like).onPressed, isNull);
    final bookmark = find.widgetWithIcon(IconButton, Icons.bookmark);
    expect(tester.widget<IconButton>(bookmark).isSelected, true);
    expect(tester.widget<IconButton>(bookmark).onPressed, isNull);
    await tester.tap(find.byTooltip('核对反馈状态'));
    expect(checks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only confirmed eligible messages can be bookmarked', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ChatMessageView(
                message: const ChatMessage(
                  'execution',
                  'assistant',
                  '<think>Hidden</think>',
                  feedbackAvailable: true,
                ),
                onToggleSaved: changes.add,
              ),
              ChatMessageView(
                message: const ChatMessage(
                  'notification',
                  'assistant',
                  'Notification',
                  source: 'notification',
                  feedbackAvailable: true,
                  saved: true,
                ),
                onToggleSaved: changes.add,
              ),
              ChatMessageView(
                message: const ChatMessage(
                  'pending',
                  'assistant',
                  'Generating',
                  feedbackAvailable: true,
                ),
                confirmed: false,
                onToggleSaved: changes.add,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Hidden'), findsNothing);
    expect(find.text('无可显示的正文'), findsOneWidget);
    await tester.tap(find.byTooltip('收藏'));
    await tester.tap(find.byTooltip('取消收藏'));
    expect(changes, [true, false]);
  });

  test('chat text and action colors have readable contrast in both themes', () {
    double contrast(Color first, Color second) {
      final a = first.computeLuminance();
      final b = second.computeLuminance();
      return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
    }

    for (final palette in MusePalette.values) {
      for (final brightness in Brightness.values) {
        final colors = palette.colors(brightness);
        final label = '${palette.id} ${brightness.name}';
        final pairs = [
          ('page', colors.onSurface, colors.surface),
          ('reply', colors.onSurface, colors.surfaceContainerLowest),
          ('bubble', colors.onPrimaryContainer, colors.primaryContainer),
          ('emphasis', colors.primary, colors.surfaceContainerLowest),
          ('inline code', colors.primary, colors.surfaceContainerLow),
          ('quote', colors.onSurfaceVariant, colors.surfaceContainerLow),
          ('tab label', colors.primary, colors.surface),
          (
            'tab indicator',
            colors.onSecondaryContainer,
            colors.secondaryContainer,
          ),
          ('send', colors.onTertiary, colors.tertiary),
        ];
        for (final (role, text, surface) in pairs) {
          expect(
            contrast(text, surface),
            greaterThanOrEqualTo(4.5),
            reason: '$label: $role',
          );
        }
      }
    }
  });
}
