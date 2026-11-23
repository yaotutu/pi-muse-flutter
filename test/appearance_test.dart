import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/api.dart';
import 'package:pi_muse_flutter/src/appearance.dart';
import 'package:pi_muse_flutter/src/appearance_page.dart';
import 'package:pi_muse_flutter/src/chat.dart';
import 'package:pi_muse_flutter/src/chat_page.dart';

void main() {
  test('the original indigo roles and page styling are retained', () {
    for (final (brightness, surface, card, primary, bubble, outline) in [
      (
        Brightness.light,
        0xfff7f9fb,
        0xffffffff,
        0xff00288e,
        0xffdbeafe,
        0xffe2e8f0,
      ),
      (
        Brightness.dark,
        0xff111722,
        0xff1b2433,
        0xffb8c4ff,
        0xff25395b,
        0xff364157,
      ),
    ]) {
      final colors = MusePalette.indigo.colors(brightness);
      final theme = museTheme(colors);
      expect(theme.scaffoldBackgroundColor, Color(surface));
      expect(theme.dividerColor, Color(outline));
      expect(colors.surfaceContainerLowest, Color(card));
      expect(colors.primary, Color(primary));
      expect(colors.primaryContainer, Color(bubble));
      expect(
        theme.inputDecorationTheme.focusedBorder?.borderSide,
        BorderSide(color: Color(primary), width: 1.5),
      );
    }
  });

  test(
    'appearance restores stable IDs, falling back for unknown or unreadable data',
    () async {
      for (final (id, expected) in [
        ('warm-brown', MusePalette.warmBrown),
        ('future-palette', MusePalette.indigo),
        (null, MusePalette.indigo),
      ]) {
        final settings = AppearanceSettings(
          readPalette: () async => id,
          writePalette: (_) async => fail('Restore must not write'),
        );
        addTearDown(settings.dispose);
        await settings.restore();
        expect(settings.palette, expected);
      }
      final broken = AppearanceSettings(
        readPalette: () async => throw StateError('unavailable'),
        writePalette: (_) async => fail('Restore must not write'),
      );
      addTearDown(broken.dispose);
      await broken.restore();
      expect(broken.palette, MusePalette.indigo);
    },
  );

  testWidgets(
    'failed saving reverts the palette and exposes the error on the same route',
    (tester) async {
      final save = Completer<void>();
      final writes = <String>[];
      final settings = AppearanceSettings(
        readPalette: () async => 'forest',
        writePalette: (id) {
          writes.add(id);
          return save.future;
        },
      );
      addTearDown(settings.dispose);
      await settings.restore();
      await tester.pumpWidget(
        MaterialApp(home: AppearancePage(settings: settings)),
      );
      await tester.tap(find.text('紫色'));
      await tester.pump();
      expect(settings.palette, MusePalette.violet);
      expect(find.text('正在保存…'), findsOneWidget);
      await settings.select(MusePalette.warmBrown);
      expect(writes, ['violet']);
      save.completeError(StateError('unavailable'));
      await tester.pumpAndSettle();
      expect(settings.palette, MusePalette.forest);
      expect(find.text('配色未能保存，已恢复上次设置。请重试。'), findsOneWidget);
    },
  );

  testWidgets(
    'settings can change both themes without replacing the chat or its draft',
    (tester) async {
      String? stored;
      final settings = AppearanceSettings(
        readPalette: () async => stored,
        writePalette: (id) async => stored = id,
      );
      addTearDown(settings.dispose);
      final address = Uri.parse('http://localhost');
      final chat = ChatController(MuseApi(address), () => MuseApi(address));
      addTearDown(chat.dispose);
      chat.synchronized = true;
      chat.active.revision = 'saved';
      chat.active.history = const [ChatMessage('m1', 'user', '之前的消息')];
      chat.setDraft('保留的草稿');
      final conversation = chat.active;
      final brightness = tester.binding.platformDispatcher;
      addTearDown(brightness.clearPlatformBrightnessTestValue);
      brightness.platformBrightnessTestValue = Brightness.light;
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: settings,
          builder: (_, _) => MaterialApp(
            theme: museTheme(settings.palette.colors(Brightness.light)),
            darkTheme: museTheme(settings.palette.colors(Brightness.dark)),
            home: ChatPage(
              key: ObjectKey(chat),
              chat: chat,
              appearance: settings,
              onConnection: () =>
                  fail('Changing appearance must not reconnect'),
            ),
          ),
        ),
      );
      final chatFinder = find.byType(ChatPage);
      final chatState = tester.state(chatFinder);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('服务器连接'), findsOneWidget);
      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();
      expect(find.text('配色'), findsOneWidget);
      expect(find.byType(RadioListTile<MusePalette>), findsNWidgets(4));
      await tester.tap(find.text('森林绿'));
      await tester.pumpAndSettle();
      expect(stored, 'forest');
      final palettePage = find.byType(AppearancePage);
      expect(
        Theme.of(tester.element(palettePage)).colorScheme,
        MusePalette.forest.colors(Brightness.light),
      );
      brightness.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(palettePage)).colorScheme,
        MusePalette.forest.colors(Brightness.dark),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.state(chatFinder), same(chatState));
      expect(tester.widget<ChatPage>(chatFinder).chat, same(chat));
      expect(chat.active, same(conversation));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '保留的草稿',
      );
      expect(
        Theme.of(tester.element(chatFinder)).colorScheme,
        MusePalette.forest.colors(Brightness.dark),
      );

      final restored = AppearanceSettings(
        readPalette: () async => stored,
        writePalette: (_) async => fail('Restore must not write'),
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.palette, MusePalette.forest);
    },
  );
}
