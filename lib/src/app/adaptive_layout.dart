import 'package:material_ui/material_ui.dart';

import '../shared/window_size.dart';

/// 用窗口尺寸分级，软键盘不会改变导航或分栏模式。
class WorkspaceLayout {
  const WorkspaceLayout.fromSize(this.size);

  static WorkspaceLayout of(BuildContext context) =>
      WorkspaceLayout.fromSize(MediaQuery.sizeOf(context));

  final Size size;

  bool get useRail => size.width >= 600;
  bool get useSplitPane => supportsTwoPanes(size);
  double get toolbarHeight => size.height < 480 ? kToolbarHeight : 64;
  double get sidebarWidth => size.width >= 1200 ? 280 : 240;
  double get masterPaneWidth => size.width >= 1200 ? 300 : 256;
}

enum WorkspaceDestination {
  chat('聊天', Icons.chat_bubble_outline, Icons.chat_bubble),
  agenda('日程', Icons.event_note_outlined, Icons.event_note),
  settings('设置', Icons.settings_outlined, Icons.settings);

  const WorkspaceDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// 窄窗使用底栏，较宽的窗口在布局起始侧显示导航轨。
class AdaptiveWorkspaceShell extends StatefulWidget {
  const AdaptiveWorkspaceShell({
    super.key,
    required this.layout,
    required this.destination,
    required this.onDestinationSelected,
    required this.body,
    this.drawer,
    this.onDrawerChanged,
    this.sidebar,
    this.hideBottomBar = false,
  });

  final WorkspaceLayout layout;
  final WorkspaceDestination destination;
  final ValueChanged<WorkspaceDestination> onDestinationSelected;
  final Widget body;
  final Widget? drawer;
  final DrawerCallback? onDrawerChanged;
  final Widget? sidebar;
  final bool hideBottomBar;

  static void openDrawer(BuildContext context) {
    context
        .findAncestorStateOfType<_AdaptiveWorkspaceShellState>()
        ?._scaffoldKey
        .currentState
        ?.openDrawer();
  }

  static void closeDrawer(BuildContext context) {
    context
        .findAncestorStateOfType<_AdaptiveWorkspaceShellState>()
        ?._scaffoldKey
        .currentState
        ?.closeDrawer();
  }

  @override
  State<AdaptiveWorkspaceShell> createState() => _AdaptiveWorkspaceShellState();
}

class _AdaptiveWorkspaceShellState extends State<AdaptiveWorkspaceShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _select(int index) =>
      widget.onDestinationSelected(WorkspaceDestination.values[index]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final layout = widget.layout;
    final useRail = layout.useRail;
    final body = Builder(
      builder: (context) => MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: widget.body,
      ),
    );
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: useRail ? colors.surfaceContainerLow : null,
      drawer: layout.useSplitPane ? null : widget.drawer,
      onDrawerChanged: layout.useSplitPane ? null : widget.onDrawerChanged,
      bottomNavigationBar: useRail || widget.hideBottomBar
          ? null
          : NavigationBar(
              selectedIndex: widget.destination.index,
              onDestinationSelected: _select,
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => theme.textTheme.labelMedium?.copyWith(
                  color: states.contains(WidgetState.selected)
                      ? colors.secondary
                      : colors.onSurfaceVariant,
                ),
              ),
              destinations: [
                for (final item in WorkspaceDestination.values)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: item.label,
                  ),
              ],
            ),
      body: !useRail
          ? body
          : SafeArea(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 8, bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NavigationRail(
                      minWidth: 96,
                      scrollable: true,
                      backgroundColor: colors.surfaceContainerLow,
                      labelType: NavigationRailLabelType.all,
                      selectedLabelTextStyle: theme.textTheme.labelMedium
                          ?.copyWith(color: colors.secondary),
                      selectedIndex: widget.destination.index,
                      onDestinationSelected: _select,
                      destinations: [
                        for (final item in WorkspaceDestination.values)
                          NavigationRailDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.selectedIcon),
                            label: Text(item.label),
                          ),
                      ],
                    ),
                    if (widget.sidebar case final sidebar?) ...[
                      SizedBox(
                        width: layout.sidebarWidth,
                        child: _WorkspacePane(child: sidebar),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: _WorkspacePane(child: body)),
                  ],
                ),
              ),
            ),
    );
  }
}

class _WorkspacePane extends StatelessWidget {
  const _WorkspacePane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

/// 宽窗并排显示目录与详情，其他尺寸每次显示一页。
class AdaptiveListDetail extends StatelessWidget {
  const AdaptiveListDetail({
    super.key,
    required this.split,
    required this.masterWidth,
    required this.master,
    required this.detail,
  });

  final bool split;
  final double masterWidth;
  final Widget master;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    if (!split) return master;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: masterWidth,
            child: _WorkspacePane(child: master),
          ),
          const SizedBox(width: 8),
          Expanded(child: _WorkspacePane(child: detail)),
        ],
      ),
    );
  }
}
