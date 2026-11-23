import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'appearance.dart';
import 'appearance_page.dart';
import 'chat.dart';
import 'chat_attachment_view.dart';
import 'chat_message_view.dart';
import 'workspace_files.dart';
import 'workspace_files_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.chat,
    required this.appearance,
    required this.onConnection,
  });

  final ChatController chat;
  final AppearanceSettings appearance;
  final VoidCallback onConnection;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _composer = TextEditingController();
  final _focus = FocusNode();
  final _position = PageStorageBucket();
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
    return Drawer(
      semanticLabel: '侧边导航',
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
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
                _openSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    _focus.unfocus();
    final onConnection = widget.onConnection;
    final appearance = widget.appearance;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: SafeArea(
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('外观'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => AppearancePage(settings: appearance),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('服务器连接'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    onConnection();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickSession() async {
    _focus.unfocus();
    final choice = await showDialog<_SessionChoice>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: _chat,
        builder: (context, _) {
          final colors = Theme.of(context).colorScheme;
          return AlertDialog(
            title: const Text('切换会话'),
            scrollable: true,
            contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_chat.directoryError case final String error)
                  ListTile(title: Text(error), onTap: _chat.refreshDirectory),
                for (final session in _chat.sessions)
                  ListTile(
                    shape: const StadiumBorder(),
                    title: Text(session.title),
                    leading: Icon(
                      session.id == mainSession
                          ? Icons.home_outlined
                          : Icons.chat_bubble_outline,
                    ),
                    selected: session.id == _chat.activeId,
                    selectedColor: colors.onSecondaryContainer,
                    selectedTileColor: colors.secondaryContainer,
                    onTap: () =>
                        Navigator.pop(context, _SelectSession(session.id)),
                  ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: _chat.synchronized
                    ? () => Navigator.pop(context, const _CreateSession())
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('新建会话'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _SelectSession(:final id):
        _chat.select(id);
      case _CreateSession():
        await showDialog<void>(
          context: context,
          builder: (_) => _NewSessionDialog(chat: _chat),
        );
      case null:
        break;
    }
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _ApprovalPage(chat: _chat, approval: selected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _chat,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final conversation = _chat.active;
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
        return Scaffold(
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
            title: _ChatTitle(
              title: title,
              activity: activity,
              onTap: _pickSession,
            ),
            centerTitle: true,
            actions: const [SizedBox(width: 76)],
          ),
          bottomNavigationBar: compact
              ? null
              : _ChatNavigationBar(onSettings: _openSettings),
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
                            : Align(
                                alignment: Alignment.topCenter,
                                child: ListView.separated(
                                  key: PageStorageKey(conversation.id),
                                  // 短对话从顶部开始，长对话仍以最新消息为滚动起点。
                                  shrinkWrap: true,
                                  reverse: true,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    24,
                                  ),
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
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
                                          message: message,
                                          confirmed: confirmed,
                                        ),
                                      ],
                                    );
                                  },
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
                        when !pending.running && !pending.settled)
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
                                      onRemove: _chat.pickingAttachments
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
                                  readOnly: conversation.submission != null,
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
                                  final action = running
                                      ? pending!.stopping
                                            ? null
                                            : _chat.stop
                                      : _chat.canSend &&
                                            (value.text.trim().isNotEmpty ||
                                                conversation
                                                    .draftAttachments
                                                    .isNotEmpty)
                                      ? _chat.send
                                      : null;
                                  return IconButton(
                                    key: ValueKey(running ? 'stop' : 'send'),
                                    tooltip: running ? '停止回复' : '发送',
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
                                          running
                                              ? Icons.stop_rounded
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
      },
    );
  }
}

sealed class _SessionChoice {
  const _SessionChoice();
}

class _SelectSession extends _SessionChoice {
  const _SelectSession(this.id);

  final String id;
}

class _CreateSession extends _SessionChoice {
  const _CreateSession();
}

class _ChatTitle extends StatelessWidget {
  const _ChatTitle({
    required this.title,
    required this.activity,
    required this.onTap,
  });

  final String title;
  final String? activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(48, 48),
        foregroundColor: colors.onSurface,
      ),
      child: Semantics(
        hint: '切换会话',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 18),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
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
        ),
      ),
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

class _ChatNavigationBar extends StatelessWidget {
  const _ChatNavigationBar({required this.onSettings});

  final VoidCallback onSettings;

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
        onDestinationSelected: (index) {
          if (index == 3) onSettings();
        },
        // 待办和新闻先按设计稿保留位置，迁移业务后再启用。
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble), label: '聊天'),
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
      if (mounted) Navigator.pop(context);
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
  const _ApprovalPage({required this.chat, required this.approval});

  final ChatController chat;
  final Approval approval;

  @override
  State<_ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends State<_ApprovalPage> {
  bool _busy = false;
  bool _unknown = false;
  String? _result;

  Future<void> _decide(bool approve) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? '批准这次修改？' : '拒绝这次修改？'),
        content: Text(widget.approval.path),
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
    if (!mounted || confirmed != true) return;
    await _submit(() => widget.chat.decide(widget.approval, approve));
  }

  Future<void> _submit(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        _unknown = false;
        _result = switch (result) {
          'approved' => '已批准，写入结果以服务端执行为准。',
          'denied' => '已拒绝。',
          'expired' => '这项审批已过期。',
          'cancelled' => '这项审批已取消。',
          _ => null,
        };
      });
    } catch (_) {
      if (mounted) setState(() => _unknown = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.chat,
    builder: (context, _) {
      final approval = widget.approval;
      final pending = widget.chat.approvals[approval.id];
      final needsVerification =
          _unknown || widget.chat.approvalNeedsVerification(approval.id);
      final actionable =
          widget.chat.synchronized &&
          pending?.revision == approval.revision &&
          approval.expiresAt.isAfter(DateTime.now());
      final note =
          _result ??
          (needsVerification
              ? '结果未确认，请先核对审批状态。'
              : !widget.chat.synchronized
              ? '正在重新连接，连接恢复后可继续。'
              : !actionable
              ? '这项审批已处理或失效。'
              : null);
      return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('确认文件修改')),
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
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(),
                        )
                      else if (needsVerification)
                        TextButton(
                          onPressed: () => _submit(
                            () => widget.chat.checkApproval(approval),
                          ),
                          child: const Text('核对状态'),
                        )
                      else if (actionable && _result == null) ...[
                        OutlinedButton(
                          onPressed: () => _decide(false),
                          child: const Text('拒绝'),
                        ),
                        FilledButton(
                          onPressed: () => _decide(true),
                          child: const Text('批准修改'),
                        ),
                      ] else
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('返回对话'),
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
