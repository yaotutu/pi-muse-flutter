import 'package:material_ui/material_ui.dart';

import 'approvals/approval_page.dart';
import 'approvals/chat_approval_card.dart';
import 'chat_controller.dart';
import 'chat_composer.dart';
import 'chat_transcript.dart';
import 'execution_details_page.dart';
import 'runs/chat_run_indicators.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.chat,
    required this.onReconnect,
    this.navigationLeading,
    this.toolbarHeight = kToolbarHeight,
    this.compact = false,
    this.onOpenAgendaItem,
  });

  final ChatController chat;
  final VoidCallback onReconnect;
  final Widget? navigationLeading;
  final double toolbarHeight;
  final bool compact;

  /// 打开日程里的某个事项。
  final AgendaItemOpener? onOpenAgendaItem;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _composer = TextEditingController();
  final _focus = FocusNode();
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
              subtitle:
                  pending[index].targetLabel != null &&
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
      builder: (_) => ApprovalPage(
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
        final allFileDiffApprovals = _chat.activeApprovals.every(
          (approval) => approval.isFileDiff,
        );
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
            ChatApprovalCard(
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
            LiveRunStepBar(
              run: remoteRun,
              steps: _chat.stepsOf(remoteRun),
              onOpenDetails: () => _openExecutionDetails(conversation.id),
            )
          else if (terminalNoticeStatus != null)
            TerminalRunNotice(
              status: terminalNoticeStatus,
              label: terminalNoticeLabel,
            ),
        ];
        final activity = hasApproval ? null : _chat.activityLabel;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: widget.toolbarHeight,
            backgroundColor: colors.surface,
            foregroundColor: colors.onSurface,
            surfaceTintColor: Colors.transparent,
            shadowColor: colors.shadow.withValues(alpha: 0.12),
            elevation: 1,
            scrolledUnderElevation: 1,
            titleSpacing: 0,
            leadingWidth: 76,
            leading: widget.navigationLeading,
            title: _ChatTitle(title: title, activity: activity),
            centerTitle: true,
            actions: [
              SizedBox(
                width: 76,
                child: Center(
                  child: IconButton(
                    tooltip: '会话详情',
                    onPressed: () => _openExecutionDetails(conversation.id),
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
                            child: Text(allFileDiffApprovals ? '查看修改' : '查看详情'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: ChatTranscript(
                        chat: _chat,
                        conversation: conversation,
                        messages: messages,
                        footers: footers,
                        onQuote: _focus.requestFocus,
                        onOpenAgendaItem: widget.onOpenAgendaItem,
                      ),
                    ),
                    if (_chat.expired)
                      TextButton(
                        onPressed: widget.onReconnect,
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
                    ChatComposer(
                      chat: _chat,
                      conversation: conversation,
                      focus: _focus,
                      controller: _composer,
                      compact: widget.compact,
                      running: running,
                      localRunning: localRunning,
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
