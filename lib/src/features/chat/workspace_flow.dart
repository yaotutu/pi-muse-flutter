part of 'chat_controller.dart';

/// 工作区通知、运行与审批。
///
/// 连接级通知只有一条 `/api/events`，聊天 AG-UI SSE 由草稿流程按运行管理。
class _WorkspaceFlow {
  _WorkspaceFlow(this.chat);

  final ChatController chat;

  /// 最近已结算的审批，聊天页据此保留结果卡片。
  final _recentSettledApprovals = <String, Approval>{};

  /// 决定结果未确认、需要用户核对的审批。
  final _unconfirmedApprovals = <String>{};

  /// 审批版本号，用于丢弃过期事件。
  final _approvalRevisions = <String, int>{};

  /// 各会话的审批变更计数。
  final _approvalChanges = <String, int>{};

  /// 正在运行的执行记录，键为（会话 ID，运行 ID）。
  final _runs = <(String, String), Json>{};

  /// 运行版本号，用于丢弃过期事件。
  final _runRevisions = <(String, String), int>{};

  /// 各会话最后一次结束的运行。
  final _lastRuns = <String, Json>{};

  /// 各会话的运行历史变更计数。
  final _runHistoryChanges = <String, int>{};

  /// 工作区快照版本，每次 ready 递增。
  int _snapshot = 0;

  /// 连接级通知事件，供其它功能复用同一条通知流。
  final _events = StreamController<WorkspaceEvent>.broadcast();

  /// 当前通知流。
  MuseApi? _notificationApi;

  /// 重连计时器。
  Timer? _reconnect;

  /// 连续失败次数，决定下一次重连的等待时间。
  int _retry = 0;

  /// 当前服务端实例标识，用于丢弃其他实例的事件。
  String? _instanceId;

  static const _resumeReconnectThreshold = Duration(seconds: 5);

  /// 工作区快照版本。
  int get snapshot => _snapshot;

  /// 连接级通知事件。
  Stream<WorkspaceEvent> get events => _events.stream;

  /// 订阅通知并同步当前会话。
  void start() {
    reconnect();
    unawaited(chat.refresh(chat.active));
  }

  /// 重新建立通知订阅。
  void reconnect() {
    if (chat._disposed || chat.expired) return;
    _reconnect?.cancel();
    _notificationApi?.close();
    chat.synchronized = false;
    chat._draft.cancelFollowUps();
    final transport = chat.openEvents();
    _notificationApi = transport;
    chat._changed();
    unawaited(_listen(transport));
  }

  /// 应用回到前台时对齐历史与在途流。
  void onAppResumed(Duration? backgroundDuration) {
    if (chat._disposed || chat.expired) return;
    if (!chat.synchronized ||
        _notificationApi == null ||
        (backgroundDuration != null &&
            backgroundDuration >= _resumeReconnectThreshold)) {
      _retry = 0;
      reconnect();
      return;
    }
    // 短暂切回前台且长连接仍健康时，避免强杀重连造成状态闪烁，改为轻量对齐历史与在途流。
    unawaited(chat.refresh(chat.active));
    for (final conversation in chat.conversations.values) {
      if (conversation.submission case final Submission pending
          when !pending.running &&
              !pending.settled &&
              !pending.verifying &&
              !conversation.waitingToSend) {
        unawaited(chat._draft.reconcileSubmission(conversation));
      }
    }
    chat._draft.syncAttachedStream(chat.active);
  }

  /// 关闭通知流，鉴权失效时使用。
  void closeNotifications() {
    _notificationApi?.close();
  }

  /// 释放通知流与重连计时器。
  void dispose() {
    _reconnect?.cancel();
    final transport = _notificationApi;
    _notificationApi = null;
    transport?.close();
    unawaited(_events.close());
  }

  Future<void> _listen(MuseApi transport) async {
    try {
      await for (final frame in transport.events()) {
        if (_notificationApi != transport) return;
        _applyWorkspaceEvent(frame);
      }
    } catch (error) {
      if (_notificationApi == transport) chat._checkAuth(error);
    } finally {
      transport.close();
      if (_notificationApi == transport) {
        _notificationApi = null;
        chat.synchronized = false;
        chat._draft.cancelFollowUps();
        chat._changed();
        if (!chat._disposed && !chat.expired) {
          final seconds = 1 << min(_retry++, 5);
          _reconnect = Timer(Duration(seconds: seconds), reconnect);
        }
      }
    }
  }

  void _applyWorkspaceEvent(SseFrame frame) {
    final data = frame.data;
    if (frame.event == 'ready') {
      final running = (data['sessionStatuses'] as List).cast<Json>();
      final pending = (data['pendingApprovals'] as List)
          .cast<Json>()
          .map(Approval.fromJson)
          .toList();
      final instanceId = data['instanceId'] as String;
      final sameInstance = _instanceId == instanceId;
      final previouslyRunning = sameInstance
          ? _runs.keys.toList()
          : const <(String, String)>[];
      if (!sameInstance) {
        chat._draft.cancelFollowUps();
        _lastRuns.clear();
        _runHistoryChanges.clear();
        _approvalChanges.clear();
      }
      _instanceId = instanceId;
      final snapshot = ++_snapshot;
      _runs.clear();
      _runRevisions.clear();
      chat.approvals.clear();
      for (final run in running) {
        recordRun(run);
      }
      for (final approval in pending) {
        _recordApproval(approval, snapshot: true);
      }
      _retry = 0;
      chat.synchronized = true;
      // 连接就绪后其它功能也要重新读取，通知订阅者按新快照对齐。
      _events.add((name: 'ready', data: data));
      for (final key in previouslyRunning) {
        if (!_runs.containsKey(key)) unawaited(_readMissedRun(key, snapshot));
      }
      unawaited(chat.refreshDirectory());
      for (final conversation in chat.conversations.values) {
        unawaited(chat.refresh(conversation));
        if (conversation.submission case final Submission pending
            when !pending.running &&
                !pending.settled &&
                !pending.verifying &&
                !conversation.waitingToSend) {
          unawaited(chat._draft.reconcileSubmission(conversation));
        }
      }
      chat._draft.syncAttachedStream(chat.active);
    } else if (chat.synchronized && data['instanceId'] == _instanceId) {
      switch (frame.event) {
        case 'session_status_updated':
          recordRun(data);
          if (data['sessionId'] == chat.activeId) {
            chat._draft.syncAttachedStream(chat.active);
          }
        case 'approval_pending':
          _recordApproval(Approval.fromJson(data));
        case 'approval_updated':
          _finishApproval(
            data['id'] as String,
            data['revision'] as int,
            data['sessionId'] as String?,
            status: data['status'] as String?,
            execution: data['execution'] as Json?,
          );
        case 'conversation_updated':
          final conversation = chat.conversations[data['sessionId']];
          if (conversation != null) unawaited(chat.refresh(conversation));
        case 'session_directory_updated':
          unawaited(chat.refreshDirectory());
      }
      // 其它功能复用同一条连接级通知流，按事件名自行处理。
      _events.add((name: frame.event ?? '', data: data));
    }
    chat._changed();
  }

  /// 记录一次运行状态，按版本号丢弃过期事件。
  void recordRun(Json run) {
    final key = (run['sessionId'] as String, run['runId'] as String);
    final revision = run['revision'] as int;
    if (revision <= (_runRevisions[key] ?? 0)) return;
    _runRevisions[key] = revision;
    final conversation = chat.conversations[key.$1];
    final isNew =
        conversation != null && !conversation.runsById.containsKey(key.$2);
    conversation?.runsById[key.$2] = run;
    if (run['status'] == 'running') {
      _runs[key] = run;
      if (isNew) {
        _runHistoryChanges.update(
          key.$1,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    } else if (isTerminalStatus(run['status'])) {
      _runHistoryChanges.update(
        key.$1,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      final wasRunning = _runs.remove(key) != null;
      final last = _lastRuns[key.$1];
      final endedAt = run['endedAt'] as String?;
      final lastEndedAt = last?['endedAt'] as String?;
      if (last == null ||
          last['runId'] == key.$2 ||
          lastEndedAt == null ||
          (endedAt != null && endedAt.compareTo(lastEndedAt) >= 0)) {
        _lastRuns[key.$1] = run;
      }
      final conversation = chat.conversations[key.$1];
      if (conversation == null) return;
      conversation.lastRun = run;
      if (conversation.attachedRunId == key.$2) {
        conversation.stoppingActiveRun = false;
      }
      final pending =
          conversation.submission ?? conversation._followUp?.previous;
      final isLocalRun = pending?.runId == key.$2;
      if (isLocalRun) {
        pending!.settled = true;
        if (!pending._workspaceTerminal.isCompleted) {
          pending._workspaceTerminal.complete();
        }
      }
      if (wasRunning || isLocalRun) unawaited(chat.refresh(conversation));
    }
  }

  /// 运行是否已经结束。
  bool isTerminalStatus(Object? status) =>
      status == 'succeeded' || status == 'failed' || status == 'cancelled';

  /// 指定会话是否还有正在运行的执行。
  bool hasRunningRun(String id) => _runs.keys.any((key) => key.$1 == id);

  /// 指定运行的实时状态。
  Json? runningRun(String sessionId, String runId) => _runs[(sessionId, runId)];

  /// 指定运行是否仍在跟踪中。
  bool tracksRun(String sessionId, String runId) =>
      _runs.containsKey((sessionId, runId));

  void _recordApproval(Approval approval, {bool snapshot = false}) {
    final known = _approvalRevisions[approval.id] ?? 0;
    if (approval.revision < known ||
        (!snapshot && approval.revision == known)) {
      return;
    }
    _approvalRevisions[approval.id] = approval.revision;
    if (approval.status == 'pending') chat.approvals[approval.id] = approval;
  }

  void _finishApproval(
    String id,
    int revision,
    String? sessionId, {
    String? status,
    Json? execution,
  }) {
    if (revision <= (_approvalRevisions[id] ?? 0)) return;
    _approvalRevisions[id] = revision;
    _unconfirmedApprovals.remove(id);
    final existing = chat.approvals.remove(id) ?? _recentSettledApprovals[id];
    if (existing != null && status != null && status != 'pending') {
      _recentSettledApprovals[id] = existing.copyWithResolution(
        revision: revision,
        status: status,
        execution: execution,
      );
      if (_recentSettledApprovals.length > 30) {
        _recentSettledApprovals.remove(_recentSettledApprovals.keys.first);
      }
    }
    final session = sessionId ?? existing?.sessionId;
    if (session != null) {
      _approvalChanges.update(session, (value) => value + 1, ifAbsent: () => 1);
    }
  }

  Future<void> _readMissedRun((String, String) key, int snapshot) async {
    try {
      final response = await chat.api.get(
        '/api/runs/status',
        query: {'sessionId': key.$1, 'runId': key.$2},
      );
      final run = response['status'] as Json;
      if (chat._disposed ||
          !chat.synchronized ||
          snapshot != _snapshot ||
          response['instanceId'] != _instanceId ||
          run['sessionId'] != key.$1 ||
          run['runId'] != key.$2 ||
          !isTerminalStatus(run['status']) ||
          chat.sessionEntry(key.$1) == null) {
        return;
      }
      recordRun(run);
      chat._changed();
    } catch (error) {
      if (snapshot != _snapshot || !chat.synchronized) return;
      chat._checkAuth(error);
      if (chat.expired) chat._changed();
    }
  }

  /// 指定会话正在运行的执行记录。
  Json? activeRun(String id) {
    if (!chat.synchronized) return null;
    return _runs.entries
        .where((entry) => entry.key.$1 == id)
        .map((entry) => entry.value)
        .firstOrNull;
  }

  /// 消息关联的执行记录。
  Json? runForMessage(String id, ChatMessage message) {
    final runId = message.runId;
    if (runId == null || runId.isEmpty) return null;
    final active = _runs[(id, runId)];
    if (active != null) return active;
    final stored = chat.conversations[id]?.runsById[runId];
    if (stored != null) return stored;
    final last = _lastRuns[id];
    if (last != null && last['runId'] == runId) return last;
    return null;
  }

  /// 执行步骤列表。
  List<Json> stepsOf(Json? run) {
    final steps = run?['steps'];
    if (steps is! List) return const [];
    return steps.whereType<Json>().toList(growable: false);
  }

  /// 指定会话的执行记录。
  List<Json> executionRuns(String id) {
    if (!chat.synchronized) return const [];
    final active = _runs.entries
        .where((entry) => entry.key.$1 == id)
        .map((entry) => entry.value)
        .toList();
    final last = _lastRuns[id];
    if (active.isEmpty && last != null) active.add(last);
    return active;
  }

  /// 执行历史的版本号，用于判断是否需要重新读取。
  (int, int) executionHistoryVersion(String id, {required bool approvals}) =>
      (_snapshot, (approvals ? _approvalChanges : _runHistoryChanges)[id] ?? 0);

  /// 审批决定是否需要用户核对。
  bool approvalNeedsVerification(String id) =>
      _unconfirmedApprovals.contains(id);

  /// 审批的版本号。
  int approvalRevision(String id) => _approvalRevisions[id] ?? 0;

  /// 指定会话的待确认审批。
  List<Approval> sessionApprovals(String id) => chat.approvals.values
      .where((approval) => approval.sessionId == id)
      .toList();

  /// 聊天页展示的审批，含最近已结算的卡片。
  List<Approval> chatApprovals(String sessionId) {
    if (!chat.synchronized) return const [];
    final latestRunId =
        (activeRun(sessionId)?['runId'] as String?) ??
        (chat.conversations[sessionId]?.lastRun?['runId'] as String?);
    return [
      for (final settled in _recentSettledApprovals.values)
        if (settled.sessionId == sessionId &&
            !chat.approvals.containsKey(settled.id) &&
            (settled.runId == null ||
                latestRunId == null ||
                settled.runId == latestRunId))
          settled,
      ...sessionApprovals(sessionId),
    ];
  }

  /// 读取执行详情。
  Future<Json> readExecution(String path, {Map<String, String>? query}) async {
    try {
      return await chat.api.get(path, query: query);
    } catch (error) {
      chat._checkAuth(error);
      if (chat.expired) chat._changed();
      rethrow;
    }
  }

  /// 读取审批详情。
  Future<Approval> readApprovalDetail(String sessionId, String id) async {
    final payload = await readExecution(
      '/api/approvals/${Uri.encodeComponent(id)}',
    );
    final approval = Approval.fromJson(payload['approval'] as Json? ?? payload);
    if (approval.id != id || approval.sessionId != sessionId) {
      throw const FormatException('Unexpected approval');
    }
    return approval;
  }

  /// 提交审批决定。
  Future<Approval> decide(Approval approval, bool approve) async {
    if (!chat.synchronized ||
        chat.approvals[approval.id]?.revision != approval.revision ||
        approvalNeedsVerification(approval.id) ||
        !approval.expiresAt.isAfter(DateTime.now())) {
      throw const FormatException('Approval is no longer actionable');
    }
    _unconfirmedApprovals.add(approval.id);
    try {
      final result = await chat.api.post(
        '/api/approvals/${Uri.encodeComponent(approval.id)}/decision',
        {'decision': approve ? 'approve' : 'deny'},
      );
      return _applyApprovalResult(result, approval);
    } catch (error) {
      chat._checkAuth(error);
      chat._changed();
      rethrow;
    }
  }

  /// 核对审批结果。
  Future<Approval> checkApproval(Approval approval) async {
    try {
      final result = await chat.api.get(
        '/api/approvals/${Uri.encodeComponent(approval.id)}',
      );
      return _applyApprovalResult(result, approval);
    } catch (error) {
      chat._checkAuth(error);
      chat._changed();
      rethrow;
    }
  }

  Approval _applyApprovalResult(Json result, Approval expected) {
    final payload = result['approval'] as Json? ?? result;
    final approval = Approval.fromJson(payload);
    if (approval.id != expected.id ||
        approval.sessionId != expected.sessionId ||
        approval.revision < approvalRevision(approval.id)) {
      throw const FormatException('Outdated or unexpected approval');
    }
    _unconfirmedApprovals.remove(approval.id);
    if (approval.status != 'pending') {
      _recentSettledApprovals[approval.id] = approval;
      _finishApproval(
        approval.id,
        approval.revision,
        approval.sessionId,
        status: approval.status,
        execution: approval.execution,
      );
    }
    chat._changed();
    return approval;
  }

  /// 会话被删除后清理运行与审批记录。
  void forgetSession(String id) {
    _runs.removeWhere((key, _) => key.$1 == id);
    _lastRuns.remove(id);
    _runHistoryChanges.remove(id);
    _approvalChanges.remove(id);
    chat.approvals.removeWhere((_, approval) => approval.sessionId == id);
    _recentSettledApprovals.removeWhere(
      (_, approval) => approval.sessionId == id,
    );
  }

  /// 会话历史被重置后清理对应的历史计数与已结算审批。
  void resetConversationHistory(String id) {
    _runHistoryChanges.remove(id);
    _recentSettledApprovals.removeWhere(
      (_, approval) => approval.sessionId == id,
    );
  }
}
