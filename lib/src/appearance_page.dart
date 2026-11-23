import 'package:material_ui/material_ui.dart';

import 'appearance.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key, required this.settings});

  final AppearanceSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('配色', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          '仅在本机生效。浅色和深色仍跟随系统。',
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
                          settings.saveFailed ? '配色未能保存，已恢复上次设置。请重试。' : '正在保存…',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: settings.saveFailed
                                ? colors.error
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
