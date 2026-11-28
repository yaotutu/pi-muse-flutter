import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

// 持久化 ID 独立于显示名，改文案或调整色值不影响已保存的选择。
enum MusePalette {
  system('system', '跟随系统配色'),
  indigo('indigo', '靛蓝', Color(0xff1e40af)),
  forest('forest', '森林绿', Color(0xff2e6b45)),
  warmBrown('warm-brown', '暖棕', Color(0xff885633)),
  violet('violet', '紫色', Color(0xff6945a3));

  const MusePalette(this.id, this.label, [this._seed]);

  final String id;
  final String label;
  final Color? _seed;

  static MusePalette fromId(String? id) =>
      values.where((palette) => palette.id == id).firstOrNull ?? system;

  ColorScheme colors(Brightness brightness) => ColorScheme.fromSeed(
    seedColor: _seed ?? indigo._seed!,
    brightness: brightness,
  );
}

typedef SystemColorSchemes = ({ColorScheme light, ColorScheme dark});

Future<SystemColorSchemes?> _readAndroidColors() async {
  final palette = await DynamicColorPlugin.getCorePalette();
  return palette == null
      ? null
      : (
          light: palette.toColorScheme(),
          dark: palette.toColorScheme(brightness: Brightness.dark),
        );
}

ThemeData museTheme(ColorScheme colors) {
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: colors.outline),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    appBarTheme: AppBarThemeData(
      toolbarHeight: 64,
      backgroundColor: colors.surface,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: colors.surfaceContainer,
      labelPadding: const EdgeInsets.only(top: 2),
    ),
    dividerColor: colors.outlineVariant,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    ),
  );
}

String themeModeId(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'system',
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
};

ThemeMode themeModeFromId(String? id) => switch (id) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

Future<String?> _noopRead() async => null;
Future<void> _noopWrite(String _) async {}

class AppearanceSettings extends ChangeNotifier {
  AppearanceSettings({
    required Future<String?> Function() readPalette,
    required Future<void> Function(String) writePalette,
    Future<SystemColorSchemes?> Function() readSystemColors =
        _readAndroidColors,
    Future<String?> Function() readThemeMode = _noopRead,
    Future<void> Function(String) writeThemeMode = _noopWrite,
  }) : _readPalette = readPalette,
       _writePalette = writePalette,
       _readSystemColors = readSystemColors,
       _readThemeMode = readThemeMode,
       _writeThemeMode = writeThemeMode;

  final Future<String?> Function() _readPalette;
  final Future<void> Function(String) _writePalette;
  final Future<SystemColorSchemes?> Function() _readSystemColors;
  final Future<String?> Function() _readThemeMode;
  final Future<void> Function(String) _writeThemeMode;
  MusePalette _palette = MusePalette.system;
  SystemColorSchemes? _systemColors;
  ThemeMode _themeMode = ThemeMode.system;
  bool _saving = false;
  bool _saveFailed = false;
  bool _disposed = false;

  MusePalette get palette => _palette;
  ThemeMode get themeMode => _themeMode;
  bool get saving => _saving;
  bool get saveFailed => _saveFailed;
  bool get hasSystemColors => _systemColors != null;

  ColorScheme colorsFor(MusePalette palette, Brightness brightness) {
    if (_systemColors case final system? when palette == MusePalette.system) {
      return brightness == Brightness.dark ? system.dark : system.light;
    }
    return palette.colors(brightness);
  }

  Future<void> refreshSystemColors() async {
    try {
      final colors = await _readSystemColors();
      if (_disposed || colors == _systemColors) return;
      _systemColors = colors;
      notifyListeners();
    } on PlatformException {
      // 系统暂时未提供配色时，沿用上次读到的色板或靛蓝。
    }
  }

  Future<void> restore() async {
    MusePalette savedPalette;
    try {
      savedPalette = MusePalette.fromId(await _readPalette());
    } catch (_) {
      savedPalette = MusePalette.system;
    }
    ThemeMode savedThemeMode;
    try {
      savedThemeMode = themeModeFromId(await _readThemeMode());
    } catch (_) {
      savedThemeMode = ThemeMode.system;
    }
    if (_disposed) return;
    _palette = savedPalette;
    _themeMode = savedThemeMode;
    notifyListeners();
  }

  Future<void> _persist({
    required void Function() apply,
    required void Function() revert,
    required Future<void> Function() write,
  }) async {
    apply();
    _saving = true;
    _saveFailed = false;
    notifyListeners();
    try {
      await write();
    } catch (_) {
      revert();
      _saveFailed = true;
    } finally {
      _saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> select(MusePalette palette) async {
    if (_disposed || _saving || palette == _palette) return;
    final previous = _palette;
    await _persist(
      apply: () => _palette = palette,
      revert: () => _palette = previous,
      write: () => _writePalette(palette.id),
    );
  }

  Future<void> selectThemeMode(ThemeMode mode) async {
    if (_disposed || _saving || mode == _themeMode) return;
    final previous = _themeMode;
    await _persist(
      apply: () => _themeMode = mode,
      revert: () => _themeMode = previous,
      write: () => _writeThemeMode(themeModeId(mode)),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
