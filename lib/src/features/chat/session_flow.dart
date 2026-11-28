part of 'chat_controller.dart';

/// 一次会话变更的待确认内容。
typedef _SessionChange = ({
  String? title,
  SessionScheduleDisposition? disposition,
});

/// 会话目录与历史读取。
class _SessionFlow {
  _SessionFlow(this.chat);

  final ChatController chat;

  /// 待确认的会话变更。
  final _sessionChanges = <String, _SessionChange>{};

  /// 正在提交的会话变更。
  final _busySessionChanges = <String>{};

  /// 目录读取期间再次收到失效通知。
  bool _directoryDirty = false;

  /// 在途的目录读取。
  Future<bool>? _directoryRead;

  /// 刷新会话目录。
  Future<bool> refreshDirectory() {
    _directoryDirty = true;
    return _directoryRead ??= _readDirectory();
  }

  Future<bool> _readDirectory() async {
    try {
      do {
        _directoryDirty = false;
        final data = await chat.api.get('/api/sessions');
        if (chat._disposed) return false;
        // 通知或写后核对会使在途快照失效。只采用下一次请求的结果。
        if (_directoryDirty) continue;
        final entries = (data['sessions'] as List)
            .cast<Json>()
            .map(SessionEntry.fromJson)
            .toList();
        final ids = entries.map((session) => session.id).toSet();
        if (!ids.contains(mainSession) || ids.length != entries.length) {
          throw const FormatException();
        }
        chat.sessions = entries;
        chat.directoryError = null;
        final knownIds = {...chat.conversations.keys, ..._sessionChanges.keys};
        for (final id in knownIds.where((id) => !ids.contains(id))) {
          _forgetSession(id);
        }
      } while (_directoryDirty);
      return true;
    } catch (error) {
      chat._checkAuth(error);
      chat.directoryError = '读取会话失败，点此重试';
      return false;
    } finally {
      _directoryRead = null;
      chat._changed();
    }
  }

  /// 会话目录条目。
  SessionEntry? sessionEntry(String id) =>
      chat.sessions.where((session) => session.id == id).firstOrNull;

  /// 会话变更是否正在进行。
  bool sessionChangeBusy(String id) => _busySessionChanges.contains(id);

  /// 待确认的会话标题。
  String? pendingSessionTitle(String id) => _sessionChanges[id]?.title;

  /// 待确认的会话删除处置方式。
  SessionScheduleDisposition? pendingSessionDeletion(String id) =>
      _sessionChanges[id]?.disposition;

  String sessionPath(String id) => '/api/sessions/${Uri.encodeComponent(id)}';

  /// 读取会话关联的任务与监控。
  Future<SessionSchedules> readSessionSchedules(String id) async {
    try {
      final data = await chat.api.get('${sessionPath(id)}/schedules');
      return SessionSchedules.fromJson(data);
    } catch (error) {
      chat._checkAuth(error);
      chat._changed();
      rethrow;
    }
  }

  /// 重命名会话。
  Future<SessionChangeResult> renameSession(String id, String input) {
    final title = input.trim();
    if (title.isEmpty || title.length > 200) {
      throw const FormatException('Invalid session title');
    }
    return _submitSessionChange(
      id,
      (title: title, disposition: null),
      () async {
        final data = await chat.api.patch(sessionPath(id), {'title': title});
        final entry = SessionEntry.fromJson(data['session'] as Json);
        if (entry.id != id || entry.title != title) {
          throw const FormatException();
        }
        if (chat._disposed) return;
        chat.sessions = chat.sessions
            .map((row) => row.id == id ? entry : row)
            .toList();
      },
    );
  }

  /// 删除会话。
  Future<SessionChangeResult> deleteSession(
    String id,
    SessionSchedules schedules,
    SessionScheduleDisposition disposition,
  ) => _submitSessionChange(
    id,
    (title: null, disposition: disposition),
    () async {
      final data = await chat.api.delete(sessionPath(id), {
        'scheduleRevision': schedules.revision,
        'scheduleDisposition': disposition.value,
      });
      if (data['ok'] != true || (data['removed'] as Json)['sessions'] != 1) {
        throw const FormatException();
      }
      if (chat._disposed) return;
      chat.sessions = chat.sessions.where((row) => row.id != id).toList();
      _forgetSession(id);
    },
  );

  Future<SessionChangeResult> _submitSessionChange(
    String id,
    _SessionChange change,
    Future<void> Function() submit,
  ) async {
    final previous = _sessionChanges[id];
    if (chat._disposed ||
        chat.expired ||
        !chat.synchronized ||
        id == mainSession ||
        sessionEntry(id) == null ||
        sessionChangeBusy(id) ||
        (previous != null &&
            (previous.disposition == null ||
                previous.disposition != change.disposition))) {
      throw const FormatException('Session change is not available');
    }
    _sessionChanges[id] = change;
    final conversation = chat.conversations[id];
    if (change.disposition != null && conversation != null) {
      chat._draft.cancelFollowUp(conversation);
    }
    _busySessionChanges.add(id);
    chat._changed();
    try {
      await submit();
      _sessionChanges.remove(id);
      if (!chat._disposed) unawaited(chat.refreshDirectory());
      return SessionChangeResult.confirmed;
    } catch (error) {
      chat._checkAuth(error);
      if (error is! ApiException ||
          error.status == 0 ||
          error.status == 408 ||
          error.status == 404 ||
          error.status >= 500) {
        return await _verifySessionChange(id, change);
      }
      if (previous == null) {
        _sessionChanges.remove(id);
      } else if (sessionEntry(id) != null) {
        _sessionChanges[id] = previous;
      }
      rethrow;
    } finally {
      _busySessionChanges.remove(id);
      chat._changed();
    }
  }

  /// 核对上一次会话变更的结果。
  Future<SessionChangeResult> verifySessionChange(String id) async {
    final change = _sessionChanges[id];
    if (change == null || !_busySessionChanges.add(id)) {
      return SessionChangeResult.unknown;
    }
    chat._changed();
    try {
      return await _verifySessionChange(id, change);
    } finally {
      _busySessionChanges.remove(id);
      chat._changed();
    }
  }

  Future<SessionChangeResult> _verifySessionChange(
    String id,
    _SessionChange change,
  ) async {
    if (chat._disposed || !await refreshDirectory()) {
      return SessionChangeResult.unknown;
    }
    final entry = sessionEntry(id);
    if (change.disposition != null && entry != null) {
      return SessionChangeResult.unknown;
    }
    _sessionChanges.remove(id);
    return entry?.title == change.title
        ? SessionChangeResult.confirmed
        : SessionChangeResult.differentTitle;
  }

  void _forgetSession(String id) {
    _sessionChanges.remove(id);
    final removed = chat.conversations.remove(id);
    if (removed != null) {
      chat._draft.clearFollowUp(removed);
      chat._draft.detachAttachedStream(removed, clearReplies: true);
    }
    chat._workspace.forgetSession(id);
    if (chat.activeId == id) select(mainSession);
  }

  /// 切换当前会话。
  void select(String id) {
    if (id == chat.activeId) return;
    final previous = chat.conversations[chat.activeId];
    if (previous != null) chat._draft.detachAttachedStream(previous);
    chat.activeId = id;
    chat.conversations.putIfAbsent(id, () => Conversation(id));
    unawaited(chat.refresh(chat.active));
    chat._draft.syncAttachedStream(chat.active);
    chat._changed();
  }

  /// 新建会话。
  Future<void> createSession(String title) async {
    final response = await chat.api.post('/api/sessions', {'title': title});
    if (chat._disposed) return;
    final entry = SessionEntry.fromJson(response['session'] as Json);
    chat.sessions = [...chat.sessions, entry];
    select(entry.id);
    unawaited(chat.refreshDirectory());
  }

  /// 刷新会话历史。
  Future<void> refresh(Conversation conversation) {
    if (!chat._owns(conversation)) return Future.value();
    conversation.dirty = true;
    if (conversation.submission?.running == true) return Future.value();
    return conversation.read ??= _readHistory(conversation);
  }

  Future<void> _readHistory(Conversation conversation) async {
    try {
      do {
        conversation.dirty = false;
        final data = await chat.api.get(
          '/api/conversation',
          query: {'sessionId': conversation.id},
        );
        if (!chat._owns(conversation)) return;
        if (conversation.dirty) continue;
        if (data['sessionId'] != conversation.id) throw const FormatException();
        final binding = data['piSessionId'] as String?;
        if (binding == null && conversation.id != mainSession) {
          // 删除途中可能先失去历史绑定，等目录确认后再丢弃本地草稿。
          conversation.missing = true;
          chat._draft.clearFollowUp(conversation);
          if (chat.pendingSessionDeletion(conversation.id) == null) {
            unawaited(chat.refreshDirectory());
          }
          return;
        }
        final history = (data['messages'] as List)
            .cast<Json>()
            .map(ChatMessage.fromJson)
            .toList();
        final pending = conversation.submission;
        final bindingChanged =
            conversation.binding != null && conversation.binding != binding;
        if (pending != null && !pending.running) {
          final saved = history.any(
            (message) => message.id == pending.message.id,
          );
          if (saved &&
              chat.activeRun(conversation.id) != null &&
              conversation.liveReplies.isEmpty &&
              pending.replies.isNotEmpty) {
            conversation.liveReplies.addAll(pending.replies);
          }
          if (saved || bindingChanged || binding == null) {
            conversation.submission = null;
          } else if (pending.settled) {
            if (conversation._draftIsEmpty) {
              conversation._applyDraft(pending._draft);
              conversation.error = pending.rejection ?? '服务器未保存这条消息，草稿已恢复';
            } else {
              conversation._recoveredDrafts.add(pending._draft);
              conversation.error = '上一条消息未保存，可从未发送草稿中找回';
            }
            conversation.submission = null;
          }
        }
        if (bindingChanged) {
          chat._draft.clearFollowUp(conversation);
          chat._draft.detachAttachedStream(conversation, clearReplies: true);
          conversation._clearDraft();
          conversation._recoveredDrafts.clear();
          conversation._feedbackRequests.clear();
          conversation.runsById.clear();
          chat._workspace.resetConversationHistory(conversation.id);
          conversation.attachmentError = null;
          conversation.error = null;
        }
        conversation.binding = binding;
        conversation.missing = binding == null;
        conversation.revision = data['revision'] as String;
        final lastRun = data['lastRun'];
        if (lastRun is Json) {
          conversation.lastRun = lastRun;
          final runId = lastRun['runId'];
          if (runId is String && runId.isNotEmpty) {
            conversation.runsById[runId] = lastRun;
          }
        } else if (data.containsKey('lastRun') && lastRun == null) {
          conversation.lastRun = null;
        }
        conversation.history = history;
        // 历史里已经有同一份回执时，丢掉运行期间记录的副本，避免重复展示。
        final savedReceipts = history
            .map((message) => message.agendaReceipt?.id)
            .whereType<String>()
            .toSet();
        if (savedReceipts.isNotEmpty) {
          conversation.liveAgendaReceipts.removeWhere(
            (receipt) => savedReceipts.contains(receipt.id),
          );
        }
        if (conversation.liveUserMessage case final liveUser?
            when history.any((message) => message.id == liveUser.id)) {
          conversation.liveUserMessage = null;
        }
        if (chat.activeRun(conversation.id) == null &&
            conversation._attachedStreamApi == null) {
          conversation.liveReplies.clear();
          conversation.liveUserMessage = null;
          conversation.attachedRunId = null;
          conversation.stoppingActiveRun = false;
        }
        conversation.historyError = null;
        if (chat.synchronized && binding != null) {
          unawaited(_refreshRuns(conversation, expectedBinding: binding));
        }
      } while (conversation.dirty && conversation.submission?.running != true);
    } catch (error) {
      chat._checkAuth(error);
      conversation.historyError = '消息同步失败，点此重新核对';
    } finally {
      conversation.read = null;
      chat._changed();
    }
  }

  Future<void> _refreshRuns(
    Conversation conversation, {
    required String expectedBinding,
  }) async {
    try {
      final data = await chat.api.get(
        '/api/runs',
        query: {'sessionId': conversation.id, 'limit': '50'},
      );
      if (!chat._owns(conversation) ||
          conversation.binding != expectedBinding) {
        return;
      }
      final runs = data['runs'];
      if (runs is! List) return;
      for (final item in runs) {
        if (item is! Json) continue;
        final runId = item['runId'];
        if (runId is! String || runId.isEmpty) continue;
        final existing = conversation.runsById[runId];
        if (existing == null ||
            (existing['status'] == 'running' && item['status'] != 'running')) {
          conversation.runsById[runId] = item;
        }
      }
      chat._changed();
    } catch (_) {
      // 执行记录用于辅助过程展示；失败不覆盖权威历史同步状态。
    }
  }
}
