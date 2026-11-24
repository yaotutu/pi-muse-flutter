import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'appearance.dart';
import 'appearance_page.dart';
import 'app_update.dart';
import 'app_update_sheet.dart';
import 'chat.dart';
import 'chat_attachment_view.dart';
import 'chat_message_view.dart';
import 'execution_details_page.dart';
import 'session_management.dart';
import 'sms_sync.dart';
import 'sms_sync_page.dart';
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

class _ChatPageState extends State<ChatPage> {
  final _composer = TextEditingController();
  final _focus = FocusNode();
  final _position = PageStorageBucket();
  bool _settingsSelected = false;
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

  Widget _buildDrawer(BuildContext context) {
    final scaffold = Scaffold.of(context);
    final colors = Theme.of(context).colorScheme;
    return Drawer(
      semanticLabel: '侧边导航',
      child: SafeArea(
        child: Padding(
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
                          if (created == true && scaffold.mounted) {
                            scaffold.closeDrawer();
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
                      ListTile(
                        title: Text(error),
                        onTap: _chat.refreshDirectory,
                      ),
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
                            : SessionManagementMenu(
                                chat: _chat,
                                session: session,
                              ),
                        onTap: () {
                          if (_chat.sessionEntry(session.id) == null) return;
                          _chat.select(session.id);
                          scaffold.closeDrawer();
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
                        scaffold.closeDrawer();
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => WorkspaceFilesPage(
                              files: WorkspaceFiles(_chat.api),
                            ),
                          ),
                        );
                      },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置'),
                onTap: () {
                  scaffold.closeDrawer();
                  _selectDestination(3);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectDestination(int index) {
    final showSettings = index == 3;
    if (_settingsSelected == showSettings) return;
    _focus.unfocus();
    setState(() => _settingsSelected = showSettings);
  }

  Widget _settingsHome(Widget navigation) => Scaffold(
    appBar: AppBar(automaticallyImplyLeading: false, title: const Text('设置')),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('外观'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AppearancePage(settings: widget.appearance),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('服务器连接'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onConnection,
              ),
              if (SmsSync.supported)
                ListTile(
                  leading: const Icon(Icons.sms_outlined),
                  title: const Text('短信同步'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => SmsSyncPage(
                        connectionUsesHttp: widget.connectionUsesHttp,
                      ),
                    ),
                  ),
                ),
              if (widget.updates case final updates?)
                ListTile(
                  leading: const Icon(Icons.system_update_outlined),
                  title: const Text('应用更新'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => AppUpdateSheet(controller: updates),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: navigation,
  );

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
              leading: const Icon(Icons.description_outlined),
              title: Text(pending[index].path),
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

  void _openExecutionDetails(String sessionId, String title) {
    _focus.unfocus();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ExecutionDetailsPage(
          chat: _chat,
          sessionId: sessionId,
          title: title,
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
        final running = conversation.submission?.running == true;
        final hasApproval =
            _chat.synchronized && _chat.activeApprovals.isNotEmpty;
        final pending = conversation.submission;
        final activity = hasApproval ? null : _chat.activityLabel;
        final navigation = _WorkspaceNavigationBar(
          selectedIndex: _settingsSelected ? 3 : 0,
          onDestinationSelected: _selectDestination,
        );
        final chatView = Scaffold(
          drawer: Builder(builder: _buildDrawer),
          onDrawerChanged: (open) {
            // 抽屉只改变当前路由的本地历史，主动同步 Android 的返回处理状态。
            NavigationNotification(canHandlePop: open).dispatch(context);
          },
          appBar: AppBar(
            backgroundColor: colors.surface,
            foregroundColor: colors.onSurface,
            surfaceTintColor: Colors.transparent,
            shadowColor: colors.shadow.withValues(alpha: 0.12),
            elevation: 1,
            scrolledUnderElevation: 1,
            titleSpacing: 0,
            leadingWidth: 76,
            leading: Builder(
              builder: (context) => IconButton(
                onPressed: () {
                  _focus.unfocus();
                  Scaffold.of(context).openDrawer();
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
                    tooltip: '执行详情',
                    onPressed: () =>
                        _openExecutionDetails(conversation.id, title),
                    icon: Badge(
                      isLabelVisible: hasApproval,
                      child: const Icon(Icons.monitor_heart_outlined),
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: compact ? null : navigation,
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
                          child: const Text('有文件修改待确认'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: _openApproval,
                            child: const Text('查看修改'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: PageStorage(
                        bucket: _position,
                        child: messages.isEmpty
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
                                    itemCount: messages.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 24),
                                    itemBuilder: (context, index) {
                                      final position =
                                          messages.length - index - 1;
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
                      TextButton(
                        onPressed: pending.verifying
                            ? null
                            : _chat.verifySubmission,
                        child: Text(pending.verifying ? '正在核对…' : '核对发送结果'),
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
                                            ? '停止并发送'
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: _settingsSelected,
                child: TickerMode(enabled: !_settingsSelected, child: chatView),
              ),
              if (_settingsSelected) _settingsHome(navigation),
            ],
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
      padding: const EdgeInsets.only(bottom: 32),
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

class _WorkspaceNavigationBar extends StatelessWidget {
  const _WorkspaceNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

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
        // 待办和新闻先按设计稿保留位置，迁移业务后再启用。
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: '聊天',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt),
            label: '待办',
            enabled: false,
          ),
          NavigationDestination(
            icon: Icon(Icons.newspaper_outlined),
            label: '新闻',
            enabled: false,
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? '批准这次修改？' : '拒绝这次修改？'),
        content: Text(approval.path),
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
    if (!mounted ||
        confirmed != true ||
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
          appBar: AppBar(title: Text(_history ? '审批详情' : '确认文件修改')),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SelectionArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      children: [
                        Text(
                          approval.path,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(approval.scope == 'skill' ? '技能文件' : '工作区文件'),
                        if (approval.status == 'approved' ||
                            execution != null) ...[
                          const SizedBox(height: 12),
                          Text(switch (execution?['status']) {
                            'running' => '文件提交中',
                            'succeeded' => '文件已写入',
                            'failed' => '文件写入失败',
                            'cancelled' => '文件写入已取消',
                            'unknown' => '文件写入结果待核对',
                            _ => '尚未收到文件执行回执',
                          }),
                          if (execution?['result'] case final String result)
                            Text(result),
                        ],
                        const SizedBox(height: 18),
                        _FileText(
                          label: '修改前',
                          content: approval.beforeExists
                              ? approval.before
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _FileText(label: '修改后', content: approval.after),
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
                          child: const Text('拒绝'),
                        ),
                        FilledButton(
                          onPressed: () => _decide(approval, true),
                          child: const Text('批准修改'),
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
