import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/network/api.dart';
import 'package:pi_muse_flutter/src/features/appearance/appearance.dart';
import 'package:pi_muse_flutter/src/features/appearance/appearance_page.dart';
import 'package:pi_muse_flutter/src/features/chat/chat_controller.dart';
import 'package:pi_muse_flutter/src/features/chat/chat_page.dart';
import 'package:pi_muse_flutter/src/app/workspace_page.dart';

void main() {
  test(
    'Material palettes keep required foreground contrast in light and dark',
    () {
      for (final palette in MusePalette.values) {
        for (final brightness in Brightness.values) {
          final colors = palette.colors(brightness);
          final theme = museTheme(colors);
          expect(theme.useMaterial3, isTrue);
          expect(theme.scaffoldBackgroundColor, colors.surface);
          for (final (foreground, background) in [
            (colors.onSurface, colors.surface),
            (colors.onSurfaceVariant, colors.surfaceContainerHigh),
            (colors.onPrimary, colors.primary),
            (colors.onPrimaryContainer, colors.primaryContainer),
            (colors.onSecondaryContainer, colors.secondaryContainer),
            (colors.secondary, colors.surfaceContainer),
          ]) {
            final first = foreground.computeLuminance() + 0.05;
            final second = background.computeLuminance() + 0.05;
            final ratio = first >= second ? first / second : second / first;
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '$palette/$brightness',
            );
          }
        }
      }
    },
  );

  test(
    'system color refresh works with both brightness modes and fixed choices',
    () async {
      final light = MusePalette.forest.colors(Brightness.light);
      final dark = MusePalette.forest.colors(Brightness.dark);
      SystemColorSchemes? system;
      final settings = AppearanceSettings(
        readPalette: () async => null,
        writePalette: (_) async {},
        readSystemColors: () async => system,
      );
      addTearDown(settings.dispose);
      await settings.restore();
      await settings.refreshSystemColors();
      expect(settings.palette, MusePalette.system);
      expect(settings.hasSystemColors, isFalse);
      expect(
        settings.colorsFor(settings.palette, Brightness.light),
        MusePalette.indigo.colors(Brightness.light),
      );
      system = (light: light, dark: dark);
      await settings.refreshSystemColors();
      expect(settings.hasSystemColors, isTrue);
      expect(settings.colorsFor(settings.palette, Brightness.light), light);
      expect(settings.colorsFor(settings.palette, Brightness.dark), dark);
      await settings.select(MusePalette.violet);
      await settings.refreshSystemColors();
      expect(
        settings.colorsFor(settings.palette, Brightness.dark),
        MusePalette.violet.colors(Brightness.dark),
      );
    },
  );

  test(
    'appearance restores stable palette and theme mode IDs, falling back independently',
    () async {
      for (final (id, modeId, expectedPalette, expectedMode) in [
        ('warm-brown', 'light', MusePalette.warmBrown, ThemeMode.light),
        ('forest', 'dark', MusePalette.forest, ThemeMode.dark),
        ('violet', 'system', MusePalette.violet, ThemeMode.system),
        ('future-palette', 'future-mode', MusePalette.system, ThemeMode.system),
        (null, null, MusePalette.system, ThemeMode.system),
      ]) {
        final settings = AppearanceSettings(
          readPalette: () async => id,
          writePalette: (_) async => fail('Restore must not write'),
          readThemeMode: () async => modeId,
          writeThemeMode: (_) async => fail('Restore must not write'),
        );
        addTearDown(settings.dispose);
        await settings.restore();
        expect(settings.palette, expectedPalette);
        expect(settings.themeMode, expectedMode);
      }

      final broken = AppearanceSettings(
        readPalette: () async => throw StateError('unavailable'),
        writePalette: (_) async => fail('Restore must not write'),
        readThemeMode: () async => 'light',
        writeThemeMode: (_) async => fail('Restore must not write'),
      );
      addTearDown(broken.dispose);
      await broken.restore();
      expect(broken.palette, MusePalette.system);
      expect(broken.themeMode, ThemeMode.light);

      final brokenMode = AppearanceSettings(
        readPalette: () async => 'warm-brown',
        writePalette: (_) async => fail('Restore must not write'),
        readThemeMode: () async => throw StateError('unavailable'),
        writeThemeMode: (_) async => fail('Restore must not write'),
      );
      addTearDown(brokenMode.dispose);
      await brokenMode.restore();
      expect(brokenMode.palette, MusePalette.warmBrown);
      expect(brokenMode.themeMode, ThemeMode.system);
    },
  );

  testWidgets(
    'failed saving reverts palette and theme mode and exposes the error on the same route',
    (tester) async {
      final save = Completer<void>();
      final writes = <String>[];
      final settings = AppearanceSettings(
        readPalette: () async => 'forest',
        writePalette: (id) {
          writes.add(id);
          return save.future;
        },
        readThemeMode: () async => 'dark',
        writeThemeMode: (_) async => throw StateError('unavailable'),
      );
      addTearDown(settings.dispose);
      await settings.restore();
      await tester.pumpWidget(
        MaterialApp(home: AppearancePage(settings: settings)),
      );
      await tester.ensureVisible(find.text('紫色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('紫色'));
      await tester.pump();
      expect(settings.palette, MusePalette.violet);
      expect(find.text('正在保存…'), findsOneWidget);
      await settings.select(MusePalette.warmBrown);
      expect(writes, ['violet']);
      save.completeError(StateError('unavailable'));
      await tester.pumpAndSettle();
      expect(settings.palette, MusePalette.forest);
      expect(find.text('外观设置未能保存，已恢复上次设置。请重试。'), findsOneWidget);

      await tester.ensureVisible(find.text('浅色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      expect(settings.themeMode, ThemeMode.dark);
      expect(find.text('外观设置未能保存，已恢复上次设置。请重试。'), findsOneWidget);
    },
  );

  testWidgets(
    'settings can change palette and disable auto theme switching without losing chat state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? stored;
      String? storedMode;
      final settings = AppearanceSettings(
        readPalette: () async => stored,
        writePalette: (id) async => stored = id,
        readThemeMode: () async => storedMode,
        writeThemeMode: (id) async => storedMode = id,
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
            themeMode: settings.themeMode,
            home: WorkspacePage(
              key: ObjectKey(chat),
              chat: chat,
              appearance: settings,
              connectionBuilder: (_) =>
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
      expect(find.text('主题模式'), findsOneWidget);
      expect(find.text('跟随系统自动切换'), findsOneWidget);
      expect(find.byType(RadioListTile<ThemeMode>), findsNothing);
      expect(find.text('配色'), findsOneWidget);
      expect(find.byType(RadioListTile<MusePalette>), findsNWidgets(5));
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

      // 在系统深色下关闭自动切换并改选浅色主题
      await tester.tap(find.text('跟随系统自动切换'));
      await tester.pumpAndSettle();
      expect(storedMode, 'dark');
      expect(find.text('浅色'), findsOneWidget);
      expect(find.text('深色'), findsOneWidget);
      expect(
        Theme.of(tester.element(palettePage)).colorScheme.brightness,
        Brightness.dark,
      );

      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      expect(storedMode, 'light');
      expect(
        Theme.of(tester.element(palettePage)).colorScheme,
        MusePalette.forest.colors(Brightness.light),
      );

      // 重新开启自动切换后恢复跟随系统深色，再关闭并固定为浅色验证跨页持久化
      await tester.tap(find.text('跟随系统自动切换'));
      await tester.pumpAndSettle();
      expect(storedMode, 'system');
      expect(
        Theme.of(tester.element(palettePage)).colorScheme,
        MusePalette.forest.colors(Brightness.dark),
      );

      await tester.tap(find.text('跟随系统自动切换'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      expect(storedMode, 'light');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      await tester.tap(find.text('聊天'));
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
        MusePalette.forest.colors(Brightness.light),
      );

      final restored = AppearanceSettings(
        readPalette: () async => stored,
        writePalette: (_) async => fail('Restore must not write'),
        readThemeMode: () async => storedMode,
        writeThemeMode: (_) async => fail('Restore must not write'),
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.palette, MusePalette.forest);
      expect(restored.themeMode, ThemeMode.light);
    },
  );
}
