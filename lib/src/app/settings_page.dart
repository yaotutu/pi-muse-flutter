import 'package:material_ui/material_ui.dart';

import '../features/app-update/app_update.dart';
import '../features/app-update/app_update_sheet.dart';
import '../features/appearance/appearance.dart';
import '../features/appearance/appearance_page.dart';
import '../features/mcp/mcp_page.dart';
import '../features/sms-sync/sms_sync.dart';
import '../features/sms-sync/sms_sync_page.dart';
import '../features/subagents/subagents_page.dart';
import '../network/api.dart';
import 'adaptive_layout.dart';

enum SettingsSection {
  appearance,
  connection,
  mcp,
  subagents,
  smsSync,
  updates,
}

typedef _SettingsEntry = ({
  SettingsSection section,
  IconData icon,
  String label,
  WidgetBuilder builder,
  bool enabled,
});

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.layout,
    required this.selected,
    required this.onSelected,
    required this.api,
    required this.connectionExpired,
    required this.connectionUsesHttp,
    required this.connectionBuilder,
    required this.appearance,
    required this.updates,
  });

  final WorkspaceLayout layout;
  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelected;
  final MuseApi api;
  final bool connectionExpired;
  final bool connectionUsesHttp;
  final WidgetBuilder connectionBuilder;
  final AppearanceSettings appearance;
  final AppUpdateController? updates;

  List<_SettingsEntry> get _entries => [
    (
      section: SettingsSection.appearance,
      icon: Icons.palette_outlined,
      label: '外观',
      builder: (_) => AppearancePage(settings: appearance),
      enabled: true,
    ),
    (
      section: SettingsSection.connection,
      icon: Icons.dns_outlined,
      label: '服务器连接',
      builder: connectionBuilder,
      enabled: true,
    ),
    (
      section: SettingsSection.mcp,
      icon: Icons.extension_outlined,
      label: 'MCP 服务',
      builder: (_) => McpPage(api: api),
      enabled: !connectionExpired,
    ),
    (
      section: SettingsSection.subagents,
      icon: Icons.smart_toy_outlined,
      label: 'Subagent',
      builder: (_) => SubagentsPage(api: api),
      enabled: !connectionExpired,
    ),
    if (SmsSync.supported)
      (
        section: SettingsSection.smsSync,
        icon: Icons.sms_outlined,
        label: '短信同步',
        builder: (_) =>
            SmsSyncPage(api: api, connectionUsesHttp: connectionUsesHttp),
        enabled: true,
      ),
    if (updates case final controller?)
      (
        section: SettingsSection.updates,
        icon: Icons.system_update_outlined,
        label: '应用更新',
        builder: (_) => AppUpdateSheet(controller: controller),
        enabled: true,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final split = layout.useSplitPane;
    final entries = _entries;
    final active = entries.firstWhere(
      (entry) => entry.section == selected && entry.enabled,
      orElse: () => entries.first,
    );
    final menuList = ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final entry in entries)
          ListTile(
            leading: Icon(entry.icon),
            title: Text(entry.label),
            enabled: entry.enabled,
            selected: split && active.section == entry.section,
            selectedColor: colors.onSecondaryContainer,
            selectedTileColor: colors.secondaryContainer,
            trailing: split ? null : const Icon(Icons.chevron_right),
            onTap: !entry.enabled
                ? null
                : () {
                    if (split) {
                      onSelected(entry.section);
                    } else {
                      Navigator.of(
                        context,
                      ).push<void>(MaterialPageRoute(builder: entry.builder));
                    }
                  },
          ),
      ],
    );

    final master = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: layout.toolbarHeight,
        title: const Text('设置'),
      ),
      body: SafeArea(
        top: false,
        child: split
            ? menuList
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: menuList,
                ),
              ),
      ),
    );

    return AdaptiveListDetail(
      split: split,
      masterWidth: layout.masterPaneWidth,
      master: master,
      detail: KeyedSubtree(
        key: ValueKey(active.section),
        child: Builder(builder: active.builder),
      ),
    );
  }
}
