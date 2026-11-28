import 'package:material_ui/material_ui.dart';

enum WorkspaceNavigationPlacement { bottomBar, rightRail }

/// 根据不受软键盘影响的窗口几何尺寸，统一计算应用外壳的适配规格。
class WorkspaceLayout {
  const WorkspaceLayout({
    required this.size,
    required this.navigationPlacement,
    required this.canPinSidebar,
    required this.useSplitPane,
    required this.compactToolbar,
  });

  factory WorkspaceLayout.fromSize(Size size) {
    final isLandscape = size.width > size.height;
    final useRightRail = isLandscape && size.width >= 600;
    final wideLandscape =
        isLandscape && size.width >= 840 && size.height >= 480;
    return WorkspaceLayout(
      size: size,
      navigationPlacement: useRightRail
          ? WorkspaceNavigationPlacement.rightRail
          : WorkspaceNavigationPlacement.bottomBar,
      canPinSidebar: wideLandscape,
      useSplitPane: wideLandscape,
      compactToolbar: useRightRail && size.height < 640,
    );
  }

  static WorkspaceLayout of(BuildContext context) =>
      WorkspaceLayout.fromSize(MediaQuery.sizeOf(context));

  final Size size;
  final WorkspaceNavigationPlacement navigationPlacement;
  final bool canPinSidebar;
  final bool useSplitPane;
  final bool compactToolbar;

  bool get useRightRail =>
      navigationPlacement == WorkspaceNavigationPlacement.rightRail;
  double get toolbarHeight => compactToolbar ? 48 : kToolbarHeight;
  double get sidebarWidth => size.width >= 1100 ? 280 : 248;
  double get masterPaneWidth => size.width >= 1100 ? 300 : 256;
  double get railWidth => 72;
}

class WorkspaceDestination {
  const WorkspaceDestination({
    required this.icon,
    Widget? selectedIcon,
    required this.label,
    this.enabled = true,
  }) : selectedIcon = selectedIcon ?? icon;

  final Widget icon;
  final Widget selectedIcon;
  final String label;
  final bool enabled;
}

/// 统一托管应用级导航与可选左侧常驻栏，横屏宽窗切至右侧竖排导航轨，竖屏/窄窗保持底栏。
class AdaptiveWorkspaceShell extends StatefulWidget {
  const AdaptiveWorkspaceShell({
    super.key,
    required this.layout,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.body,
    this.drawer,
    this.onDrawerChanged,
    this.sidebar,
    this.sidebarVisible = false,
    this.hideBottomBar = false,
  });

  final WorkspaceLayout layout;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<WorkspaceDestination> destinations;
  final Widget body;
  final Widget? drawer;
  final DrawerCallback? onDrawerChanged;
  final Widget? sidebar;
  final bool sidebarVisible;
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

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    if (!layout.useRightRail) {
      return Scaffold(
        key: _scaffoldKey,
        drawer: widget.drawer,
        onDrawerChanged: widget.onDrawerChanged,
        bottomNavigationBar: widget.hideBottomBar
            ? null
            : _WorkspaceBottomBar(
                selectedIndex: widget.selectedIndex,
                onDestinationSelected: widget.onDestinationSelected,
                destinations: widget.destinations,
              ),
        body: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: widget.body,
        ),
      );
    }

    final colors = Theme.of(context).colorScheme;
    final showSidebar =
        layout.canPinSidebar && widget.sidebar != null && widget.sidebarVisible;
    return Scaffold(
      key: _scaffoldKey,
      drawer: layout.canPinSidebar ? null : widget.drawer,
      onDrawerChanged: layout.canPinSidebar ? null : widget.onDrawerChanged,
      body: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Builder(
          builder: (context) => Row(
            children: [
              if (showSidebar) ...[
                SizedBox(
                  width: layout.sidebarWidth,
                  child: Material(
                    color: colors.surface,
                    child: SafeArea(right: false, child: widget.sidebar!),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colors.outlineVariant,
                ),
              ],
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeLeft: showSidebar,
                  removeRight: true,
                  child: widget.body,
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colors.outlineVariant,
              ),
              _WorkspaceRightRail(
                selectedIndex: widget.selectedIndex,
                onDestinationSelected: widget.onDestinationSelected,
                destinations: widget.destinations,
                minWidth: layout.railWidth,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceBottomBar extends StatelessWidget {
  const _WorkspaceBottomBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<WorkspaceDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bar = NavigationBarTheme(
      data: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return theme.textTheme.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? colors.primary : colors.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
            size: 24,
          ),
        ),
      ),
      child: NavigationBar(
        height: 64,
        elevation: 0,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.secondaryContainer,
        labelPadding: const EdgeInsets.only(top: 2),
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: [
          for (final dest in destinations)
            NavigationDestination(
              icon: dest.icon,
              selectedIcon: dest.selectedIcon,
              label: dest.label,
              enabled: dest.enabled,
            ),
        ],
      ),
    );
    return Material(
      color: colors.surface,
      elevation: 1,
      shadowColor: colors.shadow.withValues(alpha: 0.13),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: bar,
          ),
        ),
      ),
    );
  }
}

class _WorkspaceRightRail extends StatelessWidget {
  const _WorkspaceRightRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.minWidth,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<WorkspaceDestination> destinations;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surface,
      child: SafeArea(
        left: false,
        child: NavigationRail(
          minWidth: minWidth,
          backgroundColor: colors.surface,
          groupAlignment: 0,
          scrollable: true,
          labelType: NavigationRailLabelType.all,
          useIndicator: true,
          indicatorColor: colors.secondaryContainer,
          selectedLabelTextStyle: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
          unselectedLabelTextStyle: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.onSurfaceVariant,
          ),
          selectedIconTheme: IconThemeData(
            color: colors.onSecondaryContainer,
            size: 24,
          ),
          unselectedIconTheme: IconThemeData(
            color: colors.onSurfaceVariant,
            size: 24,
          ),
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final dest in destinations)
              NavigationRailDestination(
                icon: dest.icon,
                selectedIcon: dest.selectedIcon,
                label: Text(dest.label),
                disabled: !dest.enabled,
              ),
          ],
        ),
      ),
    );
  }
}

/// 可复用的列表与详情分栏容器：宽横屏左列表右详情，其余场景保持单页列表。
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
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(width: masterWidth, child: master),
        VerticalDivider(width: 1, thickness: 1, color: colors.outlineVariant),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: true,
            child: detail,
          ),
        ),
      ],
    );
  }
}
