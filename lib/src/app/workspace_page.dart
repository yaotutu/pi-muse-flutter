import 'package:material_ui/material_ui.dart';

import '../features/app-update/app_update.dart';
import '../features/appearance/appearance.dart';
import '../features/chat/chat_controller.dart';
import '../features/chat/chat_page.dart';
import '../features/chat/session_panel.dart';
import '../features/workspace-files/workspace_files.dart';
import '../features/workspace-files/workspace_files_page.dart';
import 'adaptive_layout.dart';
import 'settings_page.dart';

/// 装配已连接的工作区，持有应用级导航与分栏状态。
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    required this.chat,
    required this.appearance,
    required this.connectionBuilder,
    this.connectionUsesHttp = false,
    this.updates,
  });

  final ChatController chat;
  final AppearanceSettings appearance;
  final WidgetBuilder connectionBuilder;
  final bool connectionUsesHttp;
  final AppUpdateController? updates;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  static const _destinations = [
    WorkspaceDestination(
      icon: Icon(Icons.chat_bubble_outline),
      selectedIcon: Icon(Icons.chat_bubble),
      label: '聊天',
    ),
    // 待办和新闻在导航中作为禁用项展示。
    WorkspaceDestination(
      icon: Icon(Icons.task_alt),
      label: '待办',
      enabled: false,
    ),
    WorkspaceDestination(
      icon: Icon(Icons.newspaper_outlined),
      label: '新闻',
      enabled: false,
    ),
    WorkspaceDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: '设置',
    ),
  ];

  final _contentKey = GlobalKey();
  bool _settingsSelected = false;
  bool _sidebarPinned = true;
  SettingsSection _settingsSection = SettingsSection.appearance;

  void _selectDestination(int index) {
    final showSettings = index == 3;
    if (_settingsSelected == showSettings) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _settingsSelected = showSettings);
  }

  void _openConnection(WorkspaceLayout layout) {
    if (layout.useSplitPane) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _settingsSelected = true;
        _settingsSection = SettingsSection.connection;
      });
      return;
    }
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: widget.connectionBuilder));
  }

  Widget _sessionPanel(BuildContext context, {bool inDrawer = false}) {
    void closeDrawer() => AdaptiveWorkspaceShell.closeDrawer(context);
    return SessionPanel(
      chat: widget.chat,
      onSessionOpened: inDrawer ? closeDrawer : null,
      onWorkspaceFiles: () {
        if (inDrawer) closeDrawer();
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                WorkspaceFilesPage(files: WorkspaceFiles(widget.chat.api)),
          ),
        );
      },
      onSettings: inDrawer
          ? () {
              closeDrawer();
              _selectDestination(3);
            }
          : null,
    );
  }

  Widget _chatNavigation(WorkspaceLayout layout) => Builder(
    builder: (context) => IconButton(
      onPressed: () {
        FocusManager.instance.primaryFocus?.unfocus();
        if (layout.canPinSidebar) {
          setState(() => _sidebarPinned = !_sidebarPinned);
        } else {
          AdaptiveWorkspaceShell.openDrawer(context);
        }
      },
      tooltip: layout.canPinSidebar
          ? (_sidebarPinned ? '收起会话列表' : '展开会话列表')
          : '打开导航菜单',
      icon: Icon(
        layout.canPinSidebar && _sidebarPinned ? Icons.menu_open : Icons.menu,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final layout = WorkspaceLayout.of(context);
    final compact = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: !_settingsSelected,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _settingsSelected) _selectDestination(0);
      },
      child: AdaptiveWorkspaceShell(
        layout: layout,
        selectedIndex: _settingsSelected ? 3 : 0,
        onDestinationSelected: _selectDestination,
        destinations: _destinations,
        drawer: _settingsSelected
            ? null
            : Builder(
                builder: (context) => Drawer(
                  semanticLabel: '侧边导航',
                  child: SafeArea(
                    child: _sessionPanel(context, inDrawer: true),
                  ),
                ),
              ),
        onDrawerChanged: (open) {
          // 抽屉只改变当前路由的本地历史，主动同步 Android 的返回处理状态。
          NavigationNotification(canHandlePop: open).dispatch(context);
        },
        sidebar: _settingsSelected ? null : Builder(builder: _sessionPanel),
        sidebarVisible: !_settingsSelected && _sidebarPinned,
        hideBottomBar: !_settingsSelected && compact,
        body: KeyedSubtree(
          key: _contentKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: _settingsSelected,
                child: TickerMode(
                  enabled: !_settingsSelected,
                  child: ChatPage(
                    chat: widget.chat,
                    compact: compact,
                    toolbarHeight: layout.toolbarHeight,
                    navigationLeading: _chatNavigation(layout),
                    onReconnect: () => _openConnection(layout),
                  ),
                ),
              ),
              if (_settingsSelected)
                ListenableBuilder(
                  listenable: widget.chat,
                  builder: (_, _) => SettingsPage(
                    layout: layout,
                    selected: _settingsSection,
                    onSelected: (section) =>
                        setState(() => _settingsSection = section),
                    api: widget.chat.api,
                    connectionExpired: widget.chat.expired,
                    connectionUsesHttp: widget.connectionUsesHttp,
                    connectionBuilder: widget.connectionBuilder,
                    appearance: widget.appearance,
                    updates: widget.updates,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
