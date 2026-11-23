import 'package:material_ui/material_ui.dart';

// 持久化 ID 独立于显示名，改文案或调整色值不影响已保存的选择。
enum MusePalette {
  indigo('indigo', '靛蓝', Color(0xff1e40af)),
  forest('forest', '森林绿', Color(0xff2e6b45)),
  warmBrown('warm-brown', '暖棕', Color(0xff885633)),
  violet('violet', '紫色', Color(0xff6945a3));

  const MusePalette(this.id, this.label, this.seed);

  final String id;
  final String label;
  final Color seed;

  static MusePalette fromId(String? id) =>
      values.where((palette) => palette.id == id).firstOrNull ?? indigo;

  ColorScheme colors(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    if (this != indigo) return scheme;

    // 默认配色沿用 Stitch 聊天页的浅色/深色语义色。
    final dark = brightness == Brightness.dark;
    return scheme.copyWith(
      primary: dark ? const Color(0xffb8c4ff) : const Color(0xff00288e),
      onPrimary: dark ? const Color(0xff082168) : const Color(0xffffffff),
      primaryContainer: dark
          ? const Color(0xff25395b)
          : const Color(0xffdbeafe),
      onPrimaryContainer: dark
          ? const Color(0xffe0ecff)
          : const Color(0xff001b3d),
      secondaryContainer: dark
          ? const Color(0xff293b59)
          : const Color(0xffd6e3ff),
      onSecondaryContainer: dark
          ? const Color(0xffd6e3ff)
          : const Color(0xff001b3d),
      tertiary: dark ? const Color(0xffa8b8ff) : const Color(0xff1e40af),
      surface: dark ? const Color(0xff111722) : const Color(0xfff7f9fb),
      onSurface: dark ? const Color(0xffecf0f8) : const Color(0xff191c1e),
      onSurfaceVariant: dark
          ? const Color(0xffc0c7d6)
          : const Color(0xff444653),
      surfaceContainerLowest: dark
          ? const Color(0xff1b2433)
          : const Color(0xffffffff),
      surfaceContainerLow: dark
          ? const Color(0xff1e283a)
          : const Color(0xfff2f4f6),
      surfaceContainer: dark
          ? const Color(0xff253042)
          : const Color(0xffeceef0),
      surfaceContainerHigh: dark
          ? const Color(0xff303c4f)
          : const Color(0xffe6e8ea),
      outline: dark ? const Color(0xffa1abbf) : const Color(0xff757684),
      outlineVariant: dark ? const Color(0xff364157) : const Color(0xffe2e8f0),
    );
  }
}

// 页面只消费主题语义色；将来的 Android 系统取色可以提供另一套 ColorScheme。
ThemeData museTheme(ColorScheme colors) {
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  return ThemeData(
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    dividerColor: colors.outlineVariant,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(height: 1.5),
      bodyMedium: TextStyle(height: 1.5),
    ),
  );
}

class AppearanceSettings extends ChangeNotifier {
  AppearanceSettings({
    required Future<String?> Function() readPalette,
    required Future<void> Function(String) writePalette,
  }) : _readPalette = readPalette,
       _writePalette = writePalette;

  final Future<String?> Function() _readPalette;
  final Future<void> Function(String) _writePalette;
  MusePalette _palette = MusePalette.indigo;
  bool _saving = false;
  bool _saveFailed = false;
  bool _disposed = false;

  MusePalette get palette => _palette;
  bool get saving => _saving;
  bool get saveFailed => _saveFailed;

  Future<void> restore() async {
    MusePalette saved;
    try {
      saved = MusePalette.fromId(await _readPalette());
    } catch (_) {
      saved = MusePalette.indigo;
    }
    if (_disposed) return;
    _palette = saved;
    notifyListeners();
  }

  Future<void> select(MusePalette palette) async {
    if (_disposed || _saving || palette == _palette) return;
    final previous = _palette;
    _palette = palette;
    _saving = true;
    _saveFailed = false;
    notifyListeners();
    try {
      await _writePalette(palette.id);
    } catch (_) {
      _palette = previous;
      _saveFailed = true;
    } finally {
      _saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
