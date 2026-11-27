import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'adaptive_layout.dart';
import 'api.dart';
import 'appearance.dart';
import 'appearance_page.dart';
import 'app_update.dart';
import 'app_update_sheet.dart';
import 'chat.dart';
import 'chat_attachment_view.dart';
import 'chat_message_view.dart';
import 'execution_details_page.dart';
import 'mcp_page.dart';
import 'session_management.dart';
import 'sms_sync.dart';
import 'sms_sync_page.dart';
import 'subagents_page.dart';
import 'workspace_files.dart';
import 'workspace_files_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.chat,
    required this.appearance,
    required this.onConnection,
    this.connectionUsesHttp = false,
    this.updates,
  });

  final ChatController chat;
  final AppearanceSettings appearance;
  final VoidCallback onConnection;
  final bool connectionUsesHttp;
  final AppUpdateController? updates;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

enum _SettingsSection { appearance, mcp, subagents, smsSync, updates }

class _ChatPageState extends State<ChatPage> {
  static const _destinations = [
    WorkspaceDestination(
      icon: Icon(Icons.chat_bubble_outline),
      selectedIcon: Icon(Icons.chat_bubble),
      label: '聊天',
    ),
    // 待办和新闻先按设计稿保留位置，迁移业务后再启用。
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

  final _composer = TextEditingController();
  final _focus = FocusNode();
  final _position = PageStorageBucket();
  final _contentKey = GlobalKey();
  bool _settingsSelected = false;
  bool _sidebarPinned = true;
  _SettingsSection _settingsSection = _SettingsSection.appearance;
  ChatController get _chat => widget.chat;

  @override
  void initState() {
    super.initState();
    _composer.text = _chat.active.draft;
    _chat.addListener(_syncComposer);
  }

  void _syncComposer() {
    final draft = _chat.active.draft;
    if (_composer.text != draft) {
      _composer.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
  }

  @override
  void dispose() {
    _chat.removeListener(_syncComposer);
    _composer.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _buildDrawer(BuildContext context) => Drawer(
    semanticLabel: '侧边导航',
    child: SafeArea(child: _buildSessionPanel(context, inDrawer: true)),
  );

  Widget _buildSessionPanel(BuildContext context, {required bool inDrawer}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
            child: FilledButton.tonalIcon(
              onPressed: _chat.synchronized
                  ? () async {
                      final created = await showDialog<bool>(
                        context: context,
                        builder: (_) => _NewSessionDialog(chat: _chat),
                      );
                      if (created == true && inDrawer && context.mounted) {
                        AdaptiveWorkspaceShell.closeDrawer(context);
                      }
                    }
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('新建会话'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (_chat.directoryError case final String error)
                  ListTile(title: Text(error), onTap: _chat.refreshDirectory),
                for (final session in _chat.sessions)
                  ListTile(
                    key: ValueKey(session.id),
                    shape: const StadiumBorder(),
                    title: Text(
                      session.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    leading: Icon(
                      session.id == mainSession
                          ? Icons.home_outlined
                          : Icons.chat_bubble_outline,
                    ),
                    selected: session.id == _chat.activeId,
                    selectedColor: colors.onSecondaryContainer,
                    selectedTileColor: colors.secondaryContainer,
                    trailing: session.id == mainSession
                        ? null
                        : SessionManagementMenu(chat: _chat, session: session),
                    onTap: () {
                      if (_chat.sessionEntry(session.id) == null) return;
                      _chat.select(session.id);
                      if (inDrawer) {
                        AdaptiveWorkspaceShell.closeDrawer(context);
                      }
                    },
                  ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('工作区文件'),
            enabled: !_chat.expired,
            onTap: _chat.expired
                ? null
                : () {
                    if (inDrawer) {
                      AdaptiveWorkspaceShell.closeDrawer(context);
                    }
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => WorkspaceFilesPage(
                          files: WorkspaceFiles(_chat.api),
                        ),
                      ),
                    );
                  },
          ),
          if (inDrawer)
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () {
                AdaptiveWorkspaceShell.closeDrawer(context);
                _selectDestination(3);
              },
            ),
        ],
      ),
    );
  }

  void _selectDestination(int index) {
    final showSettings = index == 3;
    if (_settingsSelected == showSettings) return;
    _focus.unfocus();
    setState(() => _settingsSelected = showSettings);
  }

  _SettingsSection _resolvedSettingsSection() {
    if ((_settingsSection == _SettingsSection.mcp ||
            _settingsSection == _SettingsSection.subagents) &&
        _chat.expired) {
      return _SettingsSection.appearance;
    }
    if (_settingsSection == _SettingsSection.smsSync && !SmsSync.supported) {
      return _SettingsSection.appearance;
    }
    if (_settingsSection == _SettingsSection.updates && widget.updates == null) {
      return _SettingsSection.appearance;
    }
    return _settingsSection;
  }

  Widget _buildSettingsDetail(_SettingsSection section) => KeyedSubtree(
    key: ValueKey(section),
    child: switch (section) {
      _SettingsSection.appearance => AppearancePage(settings: widget.appearance),
      _SettingsSection.mcp => McpPage(api: _chat.api),
      _SettingsSection.subagents => SubagentsPage(api: _chat.api),
      _SettingsSection.smsSync => SmsSyncPage(
        api: _chat.api,
        connectionUsesHttp: widget.connectionUsesHttp,
      ),
      _SettingsSection.updates => AppUpdateSheet(controller: widget.updates!),
    },
  );

  Widget _settingsHome(WorkspaceLayout layout) {
    final colors = Theme.of(context).colorScheme;
    final split = layout.useSplitPane;
    final activeSection = _resolvedSettingsSection();
    void openSection(_SettingsSection section, Widget Function() builder) {
      if (split) {
        setState(() => _settingsSection = section);
      } else {
        Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => builder()),
        );
      }
    }

    final menuList = ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('外观'),
          selected: split && activeSection == _SettingsSection.appearance,
          selectedColor: colors.onSecondaryContainer,
          selectedTileColor: colors.secondaryContainer,
          trailing: split ? null : const Icon(Icons.chevron_right),
          onTap: () => openSection(
            _SettingsSection.appearance,
            () => AppearancePage(settings: widget.appearance),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('服务器连接'),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onConnection,
        ),
        ListTile(
          leading: const Icon(Icons.extension_outlined),
          title: const Text('MCP 服务'),
          enabled: !_chat.expired,
          selected: split && activeSection == _SettingsSection.mcp,
          selectedColor: colors.onSecondaryContainer,
          selectedTileColor: colors.secondaryContainer,
          trailing: split ? null : const Icon(Icons.chevron_right),
          onTap: _chat.expired
              ? null
              : () => openSection(
                  _SettingsSection.mcp,
                  () => McpPage(api: _chat.api),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.smart_toy_outlined),
          title: const Text('Subagent'),
          enabled: !_chat.expired,
          selected: split && activeSection == _SettingsSection.subagents,
          selectedColor: colors.onSecondaryContainer,
          selectedTileColor: colors.secondaryContainer,
          trailing: split ? null : const Icon(Icons.chevron_right),
          onTap: _chat.expired
              ? null
              : () => openSection(
                  _SettingsSection.subagents,
                  () => SubagentsPage(api: _chat.api),
                ),
        ),
        if (SmsSync.supported)
          ListTile(
            leading: const Icon(Icons.sms_outlined),
            title: const Text('短信同步'),
            selected: split && activeSection == _SettingsSection.smsSync,
            selectedColor: colors.onSecondaryContainer,
            selectedTileColor: colors.secondaryContainer,
            trailing: split ? null : const Icon(Icons.chevron_right),
            onTap: () => openSection(
              _SettingsSection.smsSync,
              () => SmsSyncPage(
                api: _chat.api,
                connectionUsesHttp: widget.connectionUsesHttp,
              ),
            ),
          ),
        if (widget.updates case final updates?)
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('应用更新'),
            selected: split && activeSection == _SettingsSection.updates,
            selectedColor: colors.onSecondaryContainer,
            selectedTileColor: colors.secondaryContainer,
            trailing: split ? null : const Icon(Icons.chevron_right),
            onTap: () => openSection(
              _SettingsSection.updates,
              () => AppUpdateSheet(controller: updates),
            ),
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
      detail: _buildSettingsDetail(activeSection),
    );
  }

  Future<void> _openApproval() async {
    _focus.unfocus();
    final pending = _chat.activeApprovals;
    if (pending.isEmpty || !_chat.synchronized) return;
    final Approval? approval;
    if (pending.length == 1) {
      approval = pending.single;
    } else {
      approval = await showModalBottomSheet<Approval>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView.builder(
            itemCount: pending.length,
            itemBuilder: (context, index) => ListTile(
              leading: Icon(
                pending[index].isProposal
                    ? Icons.fact_check_outlined
                    : Icons.description_outlined,
              ),
              title: Text(pending[index].displayTitle),
              subtitle: pending[index].targetLabel != null &&
                      pending[index].targetLabel != pending[index].displayTitle
                  ? Text(pending[index].targetLabel!)
                  : null,
              onTap: () => Navigator.pop(context, pending[index]),
            ),
          ),
        ),
      );
    }
    final selected = approval;
    if (!mounted || selected == null) return;
    await _showApproval(context, selected.sessionId!, selected.id, selected);
  }

  Future<void> _showApproval(
    BuildContext context,
    String sessionId,
    String id,
    Approval? pending,
  ) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _ApprovalPage(
        chat: _chat,
        sessionId: sessionId,
        id: id,
        pending: pending,
      ),
    ),
  );

  void _openExecutionDetails(String sessionId) {
    _focus.unfocus();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ExecutionDetailsPage(
          chat: _chat,
          sessionId: sessionId,
          openApproval: (context, id, pending) =>
              _showApproval(context, sessionId, id, pending),
        ),
      ),
    );
  }

  Future<void> _reportFeedbackResult(
    Conversation conversation,
    String id,
    Future<void> request,
  ) async {
    try {
      await request;
    } catch (_) {
      if (!mounted || !identical(_chat.active, conversation)) return;
      final unconfirmed =
          conversation.feedbackState(id) == FeedbackRequestState.unconfirmed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(unconfirmed ? '请在消息下方核对反馈状态' : '暂时无法更新反馈')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _chat,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final conversation = _chat.active;
        final binding = conversation.binding;
        final feedbackEnabled =
            binding != null && _chat.canChangeFeedback(conversation);
        final title =
            _chat.sessions
                .where((session) => session.id == conversation.id)
                .firstOrNull
                ?.title ??
            '会话';
        final compact = MediaQuery.viewInsetsOf(context).bottom > 0;
        final messages = conversation.messages
            .where(
              (message) =>
                  message.role == 'user' || message.role == 'assistant',
            )
            .toList();
        final localRunning = conversation.submission?.running == true;
        final remoteRun = _chat.activeRun(conversation.id);
        final running = localRunning || remoteRun != null;
        final hasApproval =
            _chat.synchronized && _chat.activeApprovals.isNotEmpty;
        final allFileDiffApprovals =
            _chat.activeApprovals.every((approval) => approval.isFileDiff);
        final chatApprovals = _chat.chatApprovals(conversation.id);
        final pending = conversation.submission;
        final lastRun = !running && pending == null && messages.isNotEmpty
            ? conversation.lastRun
            : null;
        final lastRunRunId = lastRun?['runId'] as String?;
        final matchesLatestTurn =
            messages.isNotEmpty &&
            (messages.last.role == 'user' ||
                (lastRunRunId != null &&
                    lastRunRunId.isNotEmpty &&
                    (messages.last.runId == lastRunRunId ||
                        messages.last.id == 'assistant-$lastRunRunId')));
        final String? lastRunStatus = matchesLatestTurn
            ? (lastRun?['status'] as String?)
            : null;
        final terminalNoticeStatus =
            lastRunStatus == 'failed' || lastRunStatus == 'cancelled'
            ? lastRunStatus
            : null;
        final terminalNoticeLabel = terminalNoticeStatus != null
            ? (lastRun?['label'] as String?)
            : null;
        final footers = <Widget>[
          for (final approval in chatApprovals.reversed)
            _ChatApprovalCard(
              key: ValueKey('chat-approval-${approval.id}'),
              chat: _chat,
              approval: approval,
              onOpenDetails: () => _showApproval(
                context,
                conversation.id,
                approval.id,
                approval.status == 'pending' ? approval : null,
              ),
            ),
          if (running)
            _LiveRunStepBar(
              run: remoteRun,
              steps: _chat.stepsOf(remoteRun),
              onOpenDetails: () =>
                  _openExecutionDetails(conversation.id),
            )
          else if (terminalNoticeStatus != null)
            _TerminalRunNotice(
              status: terminalNoticeStatus,
              label: terminalNoticeLabel,
            ),
        ];
        final footerCount = footers.length;
        final activity = hasApproval ? null : _chat.activityLabel;
        final layout = WorkspaceLayout.of(context);
        final chatView = Scaffold(
          appBar: AppBar(
            toolbarHeight: layout.toolbarHeight,
            backgroundColor: colors.surface,
            foregroundColor: colors.onSurface,
            surfaceTintColor: Colors.transparent,
            shadowColor: colors.shadow.withValues(alpha: 0.12),
            elevation: 1,
            scrolledUnderElevation: 1,
            titleSpacing: 0,
            leadingWidth: 76,
            leading: layout.canPinSidebar
                ? IconButton(
                    onPressed: () {
                      _focus.unfocus();
                      setState(() => _sidebarPinned = !_sidebarPinned);
                    },
                    tooltip: _sidebarPinned ? '收起会话列表' : '展开会话列表',
                    icon: Icon(
                      _sidebarPinned ? Icons.menu_open : Icons.menu,
                    ),
                  )
                : Builder(
                    builder: (context) => IconButton(
                      onPressed: () {
                        _focus.unfocus();
                        AdaptiveWorkspaceShell.openDrawer(context);
                      },
                      tooltip: '打开导航菜单',
                      icon: const Icon(Icons.menu),
                    ),
                  ),
            title: _ChatTitle(title: title, activity: activity),
            centerTitle: true,
            actions: [
              SizedBox(
                width: 76,
                child: Center(
                  child: IconButton(
                    tooltip: '会话详情',
                    onPressed: () =>
                        _openExecutionDetails(conversation.id),
                    icon: Badge(
                      isLabelVisible: hasApproval,
                      child: const Icon(Icons.more_horiz),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 768),
                child: Column(
                  children: [
                    if (hasApproval)
                      MaterialBanner(
                        content: Semantics(
                          liveRegion: true,
                          child: Text(
                            allFileDiffApprovals
                                ? '有文件修改待确认'
                                : '有 ${_chat.activeApprovals.length} 项操作待确认',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: _openApproval,
                            child: Text(
                              allFileDiffApprovals ? '查看修改' : '查看详情',
                            ),
                          ),
                        ],
                      ),
                    Expanded(
                      child: PageStorage(
                        bucket: _position,
                        child: messages.isEmpty && footerCount == 0
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    conversation.missing
                                        ? '这条会话已不存在'
                                        : conversation.revision == null
                                        ? '正在读取聊天记录…'
                                        : '今天想聊点什么？',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : NotificationListener<
                                OverscrollIndicatorNotification
                              >(
                                onNotification: (notification) {
                                  // 聊天到边缘时直接停住，不拉伸消息；不影响内层横向滚动。
                                  if (notification.depth == 0) {
                                    notification.disallowIndicator();
                                  }
                                  return false;
                                },
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: ListView.separated(
                                    key: PageStorageKey(conversation.id),
                                    // 短对话从顶部开始，长对话仍以最新消息为滚动起点。
                                    shrinkWrap: true,
                                    // 只有内容超出视口时才接收纵向拖动，避免短对话被拉伸。
                                    primary: false,
                                    reverse: true,
                                    // 从落点计算已识别的拖动，避免正文手势竞争吃掉起步距离。
                                    dragStartBehavior: DragStartBehavior.down,
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      24,
                                    ),
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior
                                            .onDrag,
                                    itemCount: messages.length + footerCount,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      if (index < footerCount) {
                                        return footers[index];
                                      }
                                      final position =
                                          messages.length -
                                          (index - footerCount) -
                                          1;
                                      final message = messages[position];
                                      final sentAt = message.sentAt?.toLocal();
                                      final previous = position == 0
                                          ? null
                                          : messages[position - 1].sentAt
                                                ?.toLocal();
                                      final confirmed =
                                          pending == null ||
                                          (message.id != pending.message.id &&
                                              !pending.replies.containsKey(
                                                message.id,
                                              ));
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (sentAt != null &&
                                              !DateUtils.isSameDay(
                                                sentAt,
                                                previous,
                                              ))
                                            _ChatDateLabel(sentAt),
                                          ChatMessageView(
                                            key: ValueKey(message.id),
                                            message: message,
                                            confirmed: confirmed,
                                            feedbackState: conversation
                                                .feedbackState(message.id),
                                            onQuote:
                                                confirmed &&
                                                    conversation.canEditDraft
                                                ? () {
                                                    if (_chat.quoteMessage(
                                                      conversation,
                                                      binding,
                                                      message.id,
                                                    )) {
                                                      _focus.requestFocus();
                                                    }
                                                  }
                                                : null,
                                            onReaction: feedbackEnabled
                                                ? (reaction) =>
                                                      _reportFeedbackResult(
                                                        conversation,
                                                        message.id,
                                                        _chat.changeReaction(
                                                          conversation,
                                                          binding,
                                                          message.id,
                                                          reaction,
                                                        ),
                                                      )
                                                : null,
                                            onToggleSaved: feedbackEnabled
                                                ? (saved) =>
                                                      _reportFeedbackResult(
                                                        conversation,
                                                        message.id,
                                                        _chat.changeSaved(
                                                          conversation,
                                                          binding,
                                                          message.id,
                                                          saved,
                                                        ),
                                                      )
                                                : null,
                                            onVerifyFeedback: feedbackEnabled
                                                ? () => _reportFeedbackResult(
                                                    conversation,
                                                    message.id,
                                                    _chat.verifyFeedback(
                                                      conversation,
                                                      binding,
                                                      message.id,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                      ),
                    ),
                    if (_chat.expired)
                      TextButton(
                        onPressed: widget.onConnection,
                        child: const Text('重新登录'),
                      )
                    else if (conversation.submission
                        case final Submission pending
                        when !pending.running &&
                            !pending.settled &&
                            !conversation.waitingToSend)
                      if (pending.reconciling || pending.verifying)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              '正在同步回复状态…',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      else
                        TextButton(
                          onPressed: _chat.verifySubmission,
                          child: const Text('当前未连上服务器，点此立即同步'),
                        )
                    else if (conversation.historyError case final String error)
                      TextButton(
                        onPressed: () => _chat.refresh(conversation),
                        child: Text(error),
                      )
                    else if (conversation.attachmentError ?? conversation.error
                        case final String error)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.error),
                        ),
                      )
                    else if (!_chat.synchronized)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            '正在连接…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    if (conversation.hasRecoveredDraft)
                      TextButton(
                        onPressed:
                            conversation.canEditDraft &&
                                !_chat.pickingAttachments
                            ? _chat.recoverDraft
                            : null,
                        child: const Text('切换未发送草稿'),
                      ),
                    if (conversation.quote case final MessageQuote quote)
                      _QuotePreview(
                        quote: quote,
                        onRemove: conversation.canEditDraft
                            ? _chat.removeQuote
                            : null,
                      ),
                    if (conversation.draftAttachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        child: SingleChildScrollView(
                          key: PageStorageKey('attachments-${conversation.id}'),
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final attachment
                                  in conversation.draftAttachments)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: SizedBox(
                                    width: 210,
                                    child: ChatAttachmentTile(
                                      key: ValueKey(attachment.id),
                                      attachment: attachment,
                                      onRemove:
                                          _chat.pickingAttachments ||
                                              !conversation.canEditDraft
                                          ? null
                                          : () => _chat.removeDraftAttachment(
                                              attachment.id,
                                            ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: ListenableBuilder(
                        listenable: _focus,
                        builder: (context, child) => DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: colors.tertiary.withValues(alpha: 0.07),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: colors.surfaceContainerLowest,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                              side: _focus.hasFocus
                                  ? BorderSide(color: colors.primary)
                                  : BorderSide.none,
                            ),
                            child: child,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: _chat.pickingAttachments
                                    ? '正在读取附件'
                                    : '添加附件',
                                onPressed: _chat.canPickAttachments
                                    ? () {
                                        _focus.unfocus();
                                        _chat.chooseAttachments();
                                      }
                                    : null,
                                icon: _chat.pickingAttachments
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        Icons.attach_file,
                                        size: 22,
                                        color: colors.outline,
                                      ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _composer,
                                  focusNode: _focus,
                                  readOnly: !conversation.canEditDraft,
                                  onChanged: _chat.setDraft,
                                  minLines: 1,
                                  maxLines: compact ? 3 : 5,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 15,
                                    letterSpacing: 0,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '发消息给 Pi Muse',
                                    hintStyle: TextStyle(color: colors.outline),
                                    filled: false,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ValueListenableBuilder(
                                valueListenable: _composer,
                                builder: (context, value, _) {
                                  final hasContent =
                                      value.text.trim().isNotEmpty ||
                                      conversation.draftAttachments.isNotEmpty;
                                  final waiting = conversation.waitingToSend;
                                  final action = running
                                      ? _chat.canStop(sendNext: hasContent)
                                            ? hasContent
                                                  ? _chat.stopAndSend
                                                  : _chat.stop
                                            : null
                                      : _chat.canSend && hasContent
                                      ? _chat.send
                                      : null;
                                  final label = waiting
                                      ? '正在停止并准备发送'
                                      : running
                                      ? hasContent
                                            ? localRunning
                                                  ? '停止并发送'
                                                  : '请先停止或等待当前回复完成'
                                            : '停止回复'
                                      : '发送';
                                  return IconButton(
                                    key: ValueKey(
                                      running || waiting ? 'stop' : 'send',
                                    ),
                                    tooltip: label,
                                    onPressed: action,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 48,
                                      height: 48,
                                    ),
                                    icon: DecoratedBox(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: action == null
                                            ? colors.surfaceContainerHigh
                                            : colors.tertiary,
                                      ),
                                      child: SizedBox.square(
                                        dimension: 36,
                                        child: Icon(
                                          running || waiting
                                              ? hasContent
                                                    ? Icons.send_outlined
                                                    : Icons.stop_rounded
                                              : Icons.arrow_upward_rounded,
                                          color: action == null
                                              ? colors.outline
                                              : colors.onTertiary,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
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
            drawer: _settingsSelected ? null : Builder(builder: _buildDrawer),
            onDrawerChanged: (open) {
              // 抽屉只改变当前路由的本地历史，主动同步 Android 的返回处理状态。
              NavigationNotification(canHandlePop: open).dispatch(context);
            },
            sidebar: _settingsSelected
                ? null
                : Builder(
                    builder: (context) =>
                        _buildSessionPanel(context, inDrawer: false),
                  ),
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
                      child: chatView,
                    ),
                  ),
                  if (_settingsSelected) _settingsHome(layout),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuotePreview extends StatelessWidget {
  const _QuotePreview({required this.quote, required this.onRemove});

  final MessageQuote quote;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 12,
            top: 4,
            bottom: 4,
          ),
          child: Row(
            children: [
              Icon(
                Icons.format_quote_outlined,
                color: colors.onSecondaryContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quote.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                    Text(
                      quote.excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '移除引用',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatTitle extends StatelessWidget {
  const _ChatTitle({required this.title, required this.activity});

  final String title;
  final String? activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (activity case final String label) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: label,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: colors.secondaryContainer.withValues(alpha: 0.55),
                shape: StadiumBorder(
                  side: BorderSide(color: colors.secondaryContainer),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: colors.primary),
                    const SizedBox(width: 4),
                    Text(
                      '工作中',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChatDateLabel extends StatelessWidget {
  const _ChatDateLabel(this.time);

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final day = DateUtils.isSameDay(time, DateTime.now())
        ? '今天'
        : localizations.formatShortDate(time);
    final clock = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: true,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: Color.alphaBlend(
              colors.surfaceContainerHigh.withValues(alpha: 0.7),
              colors.surface,
            ),
            shape: const StadiumBorder(),
            shadows: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              '$day $clock',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog({required this.chat});

  final ChatController chat;

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  final _title = TextEditingController();
  bool _working = false;
  bool _unknown = false;

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty || _working || _unknown) return;
    setState(() => _working = true);
    try {
      await widget.chat.createSession(title);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      await widget.chat.refreshDirectory();
      if (mounted) {
        setState(() {
          _working = false;
          _unknown = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: AlertDialog(
      title: const Text('新建会话'),
      content: _unknown
          ? const Text('新建结果未确认。请返回会话列表核对。')
          : TextField(
              controller: _title,
              autofocus: true,
              enabled: !_working,
              maxLength: 200,
              decoration: const InputDecoration(hintText: '会话名称'),
              onSubmitted: (_) => _create(),
              onChanged: (_) => setState(() {}),
            ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: Text(_unknown ? '返回会话列表' : '取消'),
        ),
        if (!_unknown)
          FilledButton(
            onPressed: !_working && _title.text.trim().isNotEmpty
                ? _create
                : null,
            child: const Text('创建'),
          ),
      ],
    ),
  );
}

class _ApprovalPage extends StatefulWidget {
  const _ApprovalPage({
    required this.chat,
    required this.sessionId,
    required this.id,
    required this.pending,
  });

  final ChatController chat;
  final String sessionId;
  final String id;
  final Approval? pending;

  @override
  State<_ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends State<_ApprovalPage> {
  bool _busy = false;
  bool _unknown = false;
  bool _readFailed = false;
  int? _snapshot;
  int _readRevision = 0;
  int _readTicket = 0;
  bool _reading = false;
  late Approval? _approval = widget.pending;

  bool get _history => widget.pending == null;

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_approvalChanged);
    _approvalChanged();
  }

  @override
  void dispose() {
    widget.chat.removeListener(_approvalChanged);
    super.dispose();
  }

  void _approvalChanged() {
    final chat = widget.chat;
    if (!chat.synchronized) {
      if (_snapshot != null) {
        _readTicket++;
        setState(() {
          _snapshot = null;
          _reading = false;
        });
      }
      return;
    }
    if (_busy || _unknown) return;
    final revision = chat.approvalRevision(widget.id);
    final snapshot = chat.workspaceSnapshot;
    if (_snapshot == snapshot && _readRevision == revision) return;
    final reconnected = _snapshot != snapshot;
    _snapshot = snapshot;
    _readRevision = revision;
    if (_approval == null ||
        revision > _approval!.revision ||
        (reconnected && (_history || chat.approvals[widget.id] == null))) {
      _readApproval();
    }
  }

  Future<void> _readApproval() async {
    if (!widget.chat.synchronized) return;
    final ticket = ++_readTicket;
    setState(() {
      _reading = true;
      _readFailed = false;
    });
    try {
      final approval = await widget.chat.readApprovalDetail(
        widget.sessionId,
        widget.id,
      );
      if (!mounted || ticket != _readTicket) return;
      if (approval.revision < widget.chat.approvalRevision(widget.id)) {
        throw const FormatException('Outdated approval');
      }
      setState(() => _approval = approval);
    } catch (_) {
      if (mounted && ticket == _readTicket) setState(() => _readFailed = true);
    } finally {
      if (mounted && ticket == _readTicket) setState(() => _reading = false);
    }
  }

  bool _actionable(Approval approval) =>
      !_history &&
      !_reading &&
      widget.chat.synchronized &&
      widget.chat.approvals[approval.id]?.revision == approval.revision &&
      approval.expiresAt.isAfter(DateTime.now());

  Future<void> _decide(Approval approval, bool approve) async {
    final snapshot = widget.chat.workspaceSnapshot;
    final confirmed = await _confirmApprovalDialog(context, approval, approve);
    if (!mounted ||
        !confirmed ||
        !_actionable(approval) ||
        snapshot != widget.chat.workspaceSnapshot) {
      return;
    }
    await _submit(() => widget.chat.decide(approval, approve));
  }

  Future<void> _submit(Future<Approval> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        _unknown = false;
        _approval = result;
      });
    } catch (_) {
      if (mounted) setState(() => _unknown = true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _approvalChanged();
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.chat,
    builder: (context, _) {
      final approval = _approval;
      if (approval == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('审批详情')),
          body: Center(
            child: !widget.chat.synchronized
                ? const Text('审批状态待同步')
                : _readFailed
                ? TextButton(
                    onPressed: _readApproval,
                    child: const Text('读取失败，点此重试'),
                  )
                : const CircularProgressIndicator(),
          ),
        );
      }
      final needsVerification =
          !_history &&
          (_unknown || widget.chat.approvalNeedsVerification(approval.id));
      final actionable = _actionable(approval);
      final note = needsVerification
          ? '结果未确认，请先核对审批状态。'
          : !widget.chat.synchronized
          ? '审批状态待同步'
          : approval.status != 'pending'
          ? executionStatus(approval.status)
          : !actionable && !_reading
          ? '这项审批已处理或失效。'
          : null;
      final execution = approval.execution;
      return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              _history
                  ? '审批详情'
                  : approval.isFileDiff
                  ? '确认文件修改'
                  : '确认操作',
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SelectionArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      children: [
                        Text(
                          approval.displayTitle,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(approval.scopeOrCategoryLabel),
                        if (_executionReceiptText(approval, execution)
                            case final String receipt) ...[
                          const SizedBox(height: 12),
                          Text(receipt),
                          if (execution?['result'] case final String result)
                            Text(result),
                        ],
                        const SizedBox(height: 18),
                        _ApprovalPreviewBody(approval: approval),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    children: [
                      if (note != null) Text(note),
                      if (_busy || _reading)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(),
                        )
                      else if (needsVerification)
                        TextButton(
                          onPressed: widget.chat.synchronized
                              ? () => _submit(
                                  () => widget.chat.checkApproval(approval),
                                )
                              : null,
                          child: const Text('核对状态'),
                        )
                      else if (_readFailed)
                        TextButton(
                          onPressed: _readApproval,
                          child: const Text('读取失败，点此重试'),
                        )
                      else if (actionable) ...[
                        OutlinedButton(
                          onPressed: () => _decide(approval, false),
                          child: Text(approval.denyButtonLabel),
                        ),
                        FilledButton(
                          onPressed: () => _decide(approval, true),
                          child: Text(approval.approveButtonLabel),
                        ),
                      ] else
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('返回'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<bool> _confirmApprovalDialog(
  BuildContext context,
  Approval approval,
  bool approve,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        approve
            ? (approval.isFileDiff ? '批准这次修改？' : '确认执行该操作？')
            : (approval.isFileDiff ? '拒绝这次修改？' : '拒绝该请求？'),
      ),
      content: Text(approval.targetLabel ?? approval.displayTitle),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(approve ? '确认批准' : '确认拒绝'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

String? _executionReceiptText(Approval approval, Json? execution) {
  if (approval.status != 'approved' && execution == null) return null;
  if (approval.isFileDiff) {
    return switch (execution?['status']) {
      'running' => '文件提交中',
      'succeeded' => '文件已写入',
      'failed' => '文件写入失败',
      'cancelled' => '文件写入已取消',
      'unknown' => '文件写入结果待核对',
      _ => '尚未收到文件执行回执',
    };
  }
  return switch (execution?['status']) {
    'running' => '执行中',
    'succeeded' => '已执行',
    'failed' => '执行失败',
    'cancelled' => '已取消',
    'unknown' => '执行结果待核对',
    _ => null,
  };
}

class _ApprovalPreviewBody extends StatelessWidget {
  const _ApprovalPreviewBody({required this.approval, this.compact = false});

  final Approval approval;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (approval.isFileDiff) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact && approval.path.isNotEmpty) ...[
            Text(
              approval.path,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _FileText(
            label: '修改前',
            content: approval.beforeExists ? approval.before : null,
          ),
          const SizedBox(height: 12),
          _FileText(label: '修改后', content: approval.after),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (approval.summary.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(approval.summary, style: theme.textTheme.bodyMedium),
            ),
          ),
        if (approval.target case final String target when target.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '影响目标：$target',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        if (approval.items.isNotEmpty) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < approval.items.length; i++) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${approval.items[i].label}：',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            approval.items[i].value,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    if (i != approval.items.length - 1) const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChatApprovalCard extends StatefulWidget {
  const _ChatApprovalCard({
    super.key,
    required this.chat,
    required this.approval,
    required this.onOpenDetails,
  });

  final ChatController chat;
  final Approval approval;
  final VoidCallback onOpenDetails;

  @override
  State<_ChatApprovalCard> createState() => _ChatApprovalCardState();
}

class _ChatApprovalCardState extends State<_ChatApprovalCard> {
  late bool _expanded = widget.approval.isProposal ||
      (widget.approval.before.length + widget.approval.after.length <= 240);
  bool _busy = false;
  bool _unknown = false;

  bool get _actionable =>
      widget.approval.status == 'pending' &&
      widget.chat.synchronized &&
      widget.chat.approvals[widget.approval.id]?.revision ==
          widget.approval.revision &&
      widget.approval.expiresAt.isAfter(DateTime.now());

  Future<void> _decide(bool approve) async {
    final approval = widget.approval;
    final snapshot = widget.chat.workspaceSnapshot;
    final confirmed = await _confirmApprovalDialog(context, approval, approve);
    if (!mounted ||
        !confirmed ||
        !_actionable ||
        snapshot != widget.chat.workspaceSnapshot) {
      return;
    }
    await _run(() => widget.chat.decide(approval, approve));
  }

  Future<void> _run(Future<Approval> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _unknown = false);
    } catch (_) {
      if (mounted) setState(() => _unknown = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final approval = widget.approval;
    final isPending = approval.status == 'pending';
    final needsVerify =
        isPending &&
        (_unknown || widget.chat.approvalNeedsVerification(approval.id));
    final receipt = _executionReceiptText(approval, approval.execution);
    final statusText = isPending
        ? (approval.expiresAt.isAfter(DateTime.now()) ? '待你确认' : '已过期，等待同步')
        : executionStatus(approval.status);
    final borderColor = isPending ? colors.primary : colors.outlineVariant;
    final surfaceColor = isPending
        ? colors.primaryContainer.withValues(alpha: 0.25)
        : colors.surfaceContainerLow;
    final statusColor = switch (approval.status) {
      'pending' => colors.primary,
      'approved' => colors.tertiary,
      'denied' || 'expired' => colors.error,
      _ => colors.onSurfaceVariant,
    };

    return Material(
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: isPending ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  approval.isProposal
                      ? Icons.fact_check_outlined
                      : Icons.edit_note_rounded,
                  size: 20,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    approval.displayTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    child: Text(
                      statusText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                approval.scopeOrCategoryLabel,
                if (approval.targetLabel case final String target
                    when target != approval.displayTitle)
                  target,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (receipt != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  receipt,
                  if (approval.execution?['result'] case final String detail
                      when detail.isNotEmpty)
                    detail,
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
              ),
            ],
            if (_expanded) ...[
              const SizedBox(height: 10),
              _ApprovalPreviewBody(approval: approval, compact: true),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (approval.isFileDiff)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? '收起对比' : '展开完整对比'),
                  ),
                TextButton(
                  onPressed: widget.onOpenDetails,
                  child: const Text('查看全文'),
                ),
                if (_busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (needsVerify)
                  TextButton(
                    onPressed: widget.chat.synchronized
                        ? () => _run(() => widget.chat.checkApproval(approval))
                        : null,
                    child: const Text('核对状态'),
                  )
                else if (_actionable) ...[
                  OutlinedButton(
                    onPressed: () => _decide(false),
                    child: Text(approval.denyButtonLabel),
                  ),
                  FilledButton(
                    onPressed: () => _decide(true),
                    child: Text(approval.approveButtonLabel),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FileText extends StatelessWidget {
  const _FileText({required this.label, required this.content});

  final String label;
  final String? content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
                if (content?.isNotEmpty == true)
                  IconButton(
                    tooltip: '复制$label全文',
                    icon: const Icon(Icons.content_copy, size: 18),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: content!)),
                  ),
              ],
            ),
            Text(
              content == null
                  ? '新建文件'
                  : content!.isEmpty
                  ? '空文件'
                  : content!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveRunStepBar extends StatelessWidget {
  const _LiveRunStepBar({
    required this.run,
    required this.steps,
    required this.onOpenDetails,
  });

  final Json? run;
  final List<Json> steps;
  final VoidCallback onOpenDetails;

  String _latestRecordText() {
    if (steps.isNotEmpty) {
      Json? pick = steps
          .where((s) => s['status'] == 'waiting_approval')
          .lastOrNull;
      pick ??= steps.where((s) => s['status'] == 'running').lastOrNull;
      if (pick == null) {
        final last = steps.last;
        if (last['kind'] == 'file_commit' && steps.length >= 2) {
          final prev = steps[steps.length - 2];
          final prevTool = prev['toolName'];
          if (prev['kind'] == 'tool' &&
              (prevTool == 'write' || prevTool == 'edit') &&
              prev['detail'] == last['detail']) {
            pick = prev;
          }
        }
        pick ??= last;
      }
      final title = pick['title'] as String?;
      final detail = pick['detail'] as String?;
      final text = [
        if (title != null && title.isNotEmpty) title else '正在执行',
        if (detail != null && detail.isNotEmpty) detail,
      ].join(' · ');
      return pick['status'] == 'waiting_approval' ? '等待审批 · $text' : text;
    }
    final tools = (run?['tools'] as List? ?? const []).cast<Json>();
    if (tools.isNotEmpty) {
      final label = tools.last['label'] as String?;
      if (label != null && label.isNotEmpty) return label;
    }
    final subagents = (run?['subagents'] as List? ?? const []).cast<Json>();
    if (subagents.isNotEmpty) {
      final role = subagents.last['role'] as String?;
      if (role != null && role.isNotEmpty) return '委派子代理 · $role';
    }
    final rawLabel = run?['label'];
    if (rawLabel is String && rawLabel.isNotEmpty) return rawLabel;
    return '助手正在处理中…';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final waitingApproval = steps.any((s) => s['status'] == 'waiting_approval');
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: waitingApproval
              ? colors.primary.withValues(alpha: 0.45)
              : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpenDetails,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                waitingApproval
                    ? Icons.fact_check_outlined
                    : Icons.hourglass_top_rounded,
                size: 16,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _latestRecordText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                steps.length > 1 ? '共 ${steps.length} 步' : '全部动态',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalRunNotice extends StatelessWidget {
  const _TerminalRunNotice({required this.status, this.label});

  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cancelled = status == 'cancelled';
    final customLabel = label?.trim();
    final message = cancelled
        ? (customLabel != null &&
                  customLabel.isNotEmpty &&
                  customLabel != '执行已停止'
              ? customLabel
              : '上一轮回复已停止')
        : (customLabel != null &&
                  customLabel.isNotEmpty &&
                  customLabel != '执行失败'
              ? customLabel
              : '上一轮回复未能完成，你可以重新发送或继续对话');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              cancelled ? Icons.stop_circle_outlined : Icons.info_outline,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
