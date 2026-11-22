import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'chat.dart';
import 'chat_attachment_view.dart';
import 'chat_message_view.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.chat, required this.onConnection});

  final ChatController chat;
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

  Future<void> _pickSession() async {
    _focus.unfocus();
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: _chat,
        builder: (context, _) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.53,
          minChildSize: 0.32,
          maxChildSize: 0.84,
          builder: (context, scroll) => SafeArea(
            top: false,
            child: ListView(
              controller: scroll,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '会话',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _chat.synchronized
                            ? () => Navigator.pop(context, '')
                            : null,
                        label: const Text('新建'),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
                if (_chat.directoryError case final String error)
                  ListTile(title: Text(error), onTap: _chat.refreshDirectory),
                for (final session in _chat.sessions)
                  ListTile(
                    title: Text(session.title),
                    leading: Icon(
                      session.id == mainSession
                          ? Icons.home_outlined
                          : Icons.chat_bubble_outline,
                    ),
                    trailing: session.id == _chat.activeId
                        ? const Icon(Icons.check)
                        : null,
                    selected: session.id == _chat.activeId,
                    onTap: () => Navigator.pop(context, session.id),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.isNotEmpty) {
      _chat.select(choice);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _NewSessionDialog(chat: _chat),
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
        final status = !_chat.synchronized
            ? '正在连接…'
            : hasApproval
            ? null
            : _chat.activityLabel;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: colors.surface,
            foregroundColor: colors.onSurface,
            scrolledUnderElevation: 0,
            titleSpacing: 4,
            leading: IconButton(
              onPressed: _pickSession,
              tooltip: '切换会话',
              icon: const Icon(Icons.menu_rounded),
            ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            centerTitle: false,
            actions: [
              IconButton(
                onPressed: widget.onConnection,
                tooltip: '服务器连接',
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
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
                            : ListView.builder(
                                key: PageStorageKey(conversation.id),
                                reverse: true,
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  12,
                                ),
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                itemCount: messages.length,
                                itemBuilder: (context, index) =>
                                    ChatMessageView(
                                      message:
                                          messages[messages.length - index - 1],
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
                    else if (status != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            status,
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
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: ListenableBuilder(
                        listenable: _focus,
                        builder: (context, child) => Material(
                          color: colors.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                            side: BorderSide(
                              color: _focus.hasFocus
                                  ? colors.primary
                                  : colors.outlineVariant,
                            ),
                          ),
                          child: child,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
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
                                    : const Icon(Icons.attach_file),
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
                                  decoration: InputDecoration(
                                    hintText: '发消息给 Pi Muse',
                                    hintStyle: TextStyle(
                                      color: colors.onSurfaceVariant,
                                    ),
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
                                builder: (context, value, _) =>
                                    IconButton.filled(
                                      key: ValueKey(running ? 'stop' : 'send'),
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size.square(48),
                                        disabledBackgroundColor:
                                            colors.surfaceContainer,
                                        disabledForegroundColor:
                                            colors.onSurfaceVariant,
                                      ),
                                      tooltip: running ? '停止回复' : '发送',
                                      onPressed: running
                                          ? conversation.submission!.stopping
                                                ? null
                                                : _chat.stop
                                          : _chat.canSend &&
                                                (value.text.trim().isNotEmpty ||
                                                    conversation
                                                        .draftAttachments
                                                        .isNotEmpty)
                                          ? _chat.send
                                          : null,
                                      icon: Icon(
                                        running
                                            ? Icons.stop_rounded
                                            : Icons.arrow_upward_rounded,
                                      ),
                                    ),
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
