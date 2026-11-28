import 'package:material_ui/material_ui.dart';

import '../features/agenda/agenda.dart';
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
  final _contentKey = GlobalKey();
  late final AgendaController _agenda = AgendaController(
    client: AgendaClient(widget.chat.api),
    events: widget.chat.workspaceEvents,
  );
  var _destination = WorkspaceDestination.chat;
  bool _agendaBuilt = false;
  bool _sidebarPinned = true;
  SettingsSection _settingsSection = SettingsSection.appearance;

  @override
  void initState() {
    super.initState();
    _agenda.addListener(_onAgendaChanged);
  }

  @override
  void dispose() {
    _agenda.removeListener(_onAgendaChanged);
    _agenda.dispose();
    super.dispose();
  }

  /// 聊天里的事项卡片要求打开事项时，切到日程页。
  void _onAgendaChanged() {
    if (!mounted) return;
    if (_agenda.focusItemId == null ||
        _destination == WorkspaceDestination.agenda) {
      return;
    }
    setState(() {
      _destination = WorkspaceDestination.agenda;
      _agendaBuilt = true;
    });
  }

  void _selectDestination(WorkspaceDestination destination) {
    if (destination == _destination) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _destination = destination;
      if (destination == WorkspaceDestination.agenda) _agendaBuilt = true;
    });
    // 回到日程页时重新读取，拿到服务端最新的事项。
    if (destination == WorkspaceDestination.agenda) _agenda.refresh();
  }

  void _openConnection(WorkspaceLayout layout) {
    if (layout.useSplitPane) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _destination = WorkspaceDestination.settings;
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
              _selectDestination(WorkspaceDestination.settings);
            }
          : null,
    );
  }

  Widget _chatNavigation(WorkspaceLayout layout) => Builder(
    builder: (context) => IconButton(
      onPressed: () {
        FocusManager.instance.primaryFocus?.unfocus();
        if (layout.useSplitPane) {
          setState(() => _sidebarPinned = !_sidebarPinned);
        } else {
          AdaptiveWorkspaceShell.openDrawer(context);
        }
      },
      tooltip: layout.useSplitPane
          ? (_sidebarPinned ? '收起会话列表' : '展开会话列表')
          : '打开导航菜单',
      icon: Icon(
        layout.useSplitPane && _sidebarPinned ? Icons.menu_open : Icons.menu,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final layout = WorkspaceLayout.of(context);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final onChat = _destination == WorkspaceDestination.chat;
    return PopScope(
      canPop: onChat,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !onChat) _selectDestination(WorkspaceDestination.chat);
      },
      child: AdaptiveWorkspaceShell(
        layout: layout,
        destination: _destination,
        onDestinationSelected: _selectDestination,
        drawer: onChat
            ? Builder(
                builder: (context) => Drawer(
                  semanticLabel: '侧边导航',
                  child: SafeArea(
                    child: _sessionPanel(context, inDrawer: true),
                  ),
                ),
              )
            : null,
        onDrawerChanged: (open) {
          // 抽屉只改变当前路由的本地历史，主动同步 Android 的返回处理状态。
          NavigationNotification(canHandlePop: open).dispatch(context);
        },
        sidebar: onChat && layout.useSplitPane && _sidebarPinned
            ? Builder(builder: _sessionPanel)
            : null,
        hideBottomBar:
            _destination != WorkspaceDestination.settings && keyboardVisible,
        body: KeyedSubtree(
          key: _contentKey,
          child: AppBarTheme(
            data: AppBarTheme.of(
              context,
            ).copyWith(toolbarHeight: layout.toolbarHeight),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 聊天页始终保留在树上，切到日程时草稿和阅读位置都不会丢。
                Offstage(
                  offstage: !onChat,
                  child: TickerMode(
                    enabled: onChat,
                    child: ChatPage(
                      chat: widget.chat,
                      compact: keyboardVisible,
                      navigationLeading: _chatNavigation(layout),
                      onReconnect: () => _openConnection(layout),
                      onOpenAgendaItem: _agenda.openItem,
                    ),
                  ),
                ),
                if (_agendaBuilt)
                  Offstage(
                    offstage: _destination != WorkspaceDestination.agenda,
                    child: TickerMode(
                      enabled: _destination == WorkspaceDestination.agenda,
                      child: AgendaPage(
                        agenda: _agenda,
                        keyboardVisible: keyboardVisible,
                        showCalendarPane: layout.useSplitPane,
                      ),
                    ),
                  ),
                if (_destination == WorkspaceDestination.settings)
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
      ),
    );
  }
}
