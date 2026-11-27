import 'package:material_ui/material_ui.dart';

import 'appearance.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key, required this.settings});

  final AppearanceSettings settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) {
                final theme = Theme.of(context);
                final colors = theme.colorScheme;
                final auto = settings.themeMode == ThemeMode.system;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('主题模式', style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(
                            '仅在本机生效。',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: colors.surfaceContainerLowest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: colors.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('跟随系统自动切换'),
                            subtitle: Text(
                              auto
                                  ? '自动跟随系统切换浅色或深色'
                                  : '已关闭自动切换，可手动选择浅色或深色',
                            ),
                            value: auto,
                            onChanged: settings.saving
                                ? null
                                : (enabled) {
                                    settings.selectThemeMode(
                                      enabled
                                          ? ThemeMode.system
                                          : (theme.brightness == Brightness.dark
                                              ? ThemeMode.dark
                                              : ThemeMode.light),
                                    );
                                  },
                          ),
                          if (!auto) ...[
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            RadioGroup<ThemeMode>(
                              groupValue: settings.themeMode,
                              onChanged: (mode) {
                                if (mode != null) {
                                  settings.selectThemeMode(mode);
                                }
                              },
                              child: Column(
                                children: [
                                  RadioListTile<ThemeMode>(
                                    value: ThemeMode.light,
                                    enabled: !settings.saving,
                                    selected:
                                        settings.themeMode == ThemeMode.light,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: const Text('浅色'),
                                    secondary: const Icon(
                                      Icons.light_mode_outlined,
                                    ),
                                  ),
                                  const Divider(
                                    height: 1,
                                    indent: 16,
                                    endIndent: 16,
                                  ),
                                  RadioListTile<ThemeMode>(
                                    value: ThemeMode.dark,
                                    enabled: !settings.saving,
                                    selected:
                                        settings.themeMode == ThemeMode.dark,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: const Text('深色'),
                                    secondary: const Icon(
                                      Icons.dark_mode_outlined,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('配色', style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(
                            '仅在本机生效。',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: colors.surfaceContainerLowest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: colors.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: RadioGroup<MusePalette>(
                        groupValue: settings.palette,
                        onChanged: (palette) {
                          if (palette != null) settings.select(palette);
                        },
                        child: Column(
                          children: [
                            for (final palette in MusePalette.values) ...[
                              if (palette != MusePalette.indigo)
                                Divider(height: 1, indent: 16, endIndent: 16),
                              RadioListTile<MusePalette>(
                                value: palette,
                                enabled: !settings.saving,
                                selected: settings.palette == palette,
                                controlAffinity: ListTileControlAffinity.leading,
                                title: Text(palette.label),
                                subtitle: palette == MusePalette.indigo
                                    ? const Text('默认配色')
                                    : null,
                                secondary: ExcludeSemantics(
                                  child: _PaletteSwatch(
                                    colors: palette.colors(theme.brightness),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (settings.saving || settings.saveFailed)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            settings.saveFailed
                                ? '外观设置未能保存，已恢复上次设置。请重试。'
                                : '正在保存…',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: settings.saveFailed
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: colors.surface,
      shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final color in [colors.primary, colors.primaryContainer])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: color,
                  shape: const CircleBorder(),
                ),
                child: const SizedBox.square(dimension: 14),
              ),
            ),
        ],
      ),
    ),
  );
}
