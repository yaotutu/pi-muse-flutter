part of 'chat_controller.dart';

/// 停止当前运行后自动发送下一条草稿的等待时间。
const _followUpTimeout = Duration(seconds: 15);

/// 草稿、运行与反馈流程。
class _DraftFlow {
  _DraftFlow(this.chat);

  final ChatController chat;

  /// 正在使用附件选择器的会话。
  Conversation? _attachmentPickerOwner;

  /// 本机随机数，用于生成本地消息与运行 ID。
  final _random = Random.secure();

  /// 附件选择器是否被当前会话占用。
  bool get pickingAttachments => identical(_attachmentPickerOwner, chat.active);

  /// 是否可以继续添加附件。
  bool canPickAttachments() {
    final active = chat.active;
    return _attachmentPickerOwner == null &&
        !chat.expired &&
        !active.missing &&
        chat.pendingSessionDeletion(active.id) == null &&
        active.binding != null &&
        active.canEditDraft &&
        active.draftAttachments.length < maxChatAttachments &&
        active.draftAttachmentBytes < maxChatAttachmentBytes;
  }

  /// 当前会话是否可发送。
  bool canSend() => !chat.active.waitingToSend && _canSend(chat.active);

  bool _canSend(Conversation conversation) =>
      chat._owns(conversation) &&
      !identical(_attachmentPickerOwner, conversation) &&
      chat.synchronized &&
      !chat.expired &&
      !conversation.missing &&
      chat.pendingSessionDeletion(conversation.id) == null &&
      conversation.revision != null &&
      !conversation.dirty &&
      conversation.read == null &&
      conversation.historyError == null &&
      conversation.submission == null &&
      !chat._workspace.hasRunningRun(conversation.id);

  /// 是否可以停止当前运行。
  bool canStop({required bool sendNext}) {
    final conversation = chat.active;
    final pending = conversation.submission;
    if (chat.expired || conversation.waitingToSend) return false;
    if (pending?.running == true) {
      return !pending!.stopping &&
          (!sendNext ||
              (chat.synchronized &&
                  !pickingAttachments &&
                  conversation.binding != null &&
                  chat.pendingSessionDeletion(conversation.id) == null));
    }
    if (!sendNext &&
        chat.synchronized &&
        chat.activeRun(conversation.id) != null) {
      return !conversation.stoppingActiveRun;
    }
    return false;
  }

  /// 顶部的运行状态文案。
  String? activityLabel() {
    final active = chat.active;
    final pending = active.submission;
    if (active.waitingToSend) return '正在停止并准备发送';
    if (pending?.stopping == true || active.stoppingActiveRun) return '正在停止';
    if (!chat.synchronized) return null;
    final run = chat.activeRun(active.id);
    if (run != null) {
      final label = run['label'] as String?;
      return label?.isNotEmpty == true ? label! : '正在处理';
    }
    if (pending?.running != true) return null;
    return pending!.replies.isEmpty ? '正在处理' : '正在回复';
  }

  /// 核对当前会话的发送结果。
  Future<void> verifySubmission() => reconcileSubmission(chat.active);

  /// 核对会话的发送结果，必要时回读权威运行状态。
  Future<void> reconcileSubmission(Conversation conversation) async {
    final pending = conversation.submission;
    if (!chat._owns(conversation) ||
        pending == null ||
        pending.running ||
        pending.settled ||
        pending.verifying ||
        conversation.waitingToSend) {
      return;
    }
    pending.verifying = true;
    pending.reconciling = true;
    chat._changed();
    try {
      var run = chat._workspace.runningRun(conversation.id, pending.runId);
      if (run == null) {
        final response = await chat.api.get(
          '/api/runs/status',
          query: {'sessionId': conversation.id, 'runId': pending.runId},
        );
        if (!chat._owns(conversation) || conversation.submission != pending) {
          return;
        }
        final status = response['status'];
        if (status is Json) {
          chat._workspace.recordRun(status);
          run = status;
        }
      }
      if (!chat._owns(conversation) || conversation.submission != pending) {
        return;
      }
      if (run != null && run['status'] == 'running') {
        conversation.liveUserMessage = pending.message;
        conversation.liveReplies
          ..clear()
          ..addAll(pending.replies);
        conversation.submission = null;
        conversation.error = null;
        conversation.lastRun = run;
        syncAttachedStream(conversation);
        unawaited(chat.refresh(conversation));
        return;
      }
      if (run != null && chat._workspace.isTerminalStatus(run['status'])) {
        pending.settled = true;
        pending.reconciling = false;
        conversation.lastRun = run;
        conversation.error = null;
      }
    } catch (error) {
      chat._checkAuth(error);
      if (!chat._owns(conversation) || conversation.submission != pending) {
        return;
      }
      if (error is ApiException && error.status == 404 && chat.synchronized) {
        pending.settled = true;
        pending.reconciling = false;
        pending.rejection ??= '连接中断，消息未发出，草稿已恢复';
      } else {
        pending.reconciling = false;
        conversation.error = '当前未连上服务器，联网后会自动同步';
      }
    } finally {
      pending.verifying = false;
      if (!chat._disposed && chat._owns(conversation)) {
        if (pending.settled) await chat.refresh(conversation);
        chat._changed();
      }
    }
  }

  /// 记录运行过程中推送的事项回执。
  ///
  /// 回执只是快照，聊天页据此展示卡片；历史里的同一份回执按 ID 去重。
  void _recordAgendaReceipt(Conversation conversation, Json data) {
    final receipt = agendaReceiptFromEvent(data);
    if (receipt == null) return;
    if (!chat._owns(conversation)) return;
    conversation.addAgendaReceipt(receipt);
    chat._changed();
  }

  /// 断开当前会话挂接的运行流。
  void detachAttachedStream(
    Conversation conversation, {
    bool clearReplies = false,
  }) {
    final streamApi = conversation._attachedStreamApi;
    conversation._attachedStreamApi = null;
    streamApi?.close();
    if (clearReplies) {
      conversation.attachedRunId = null;
      conversation.liveReplies.clear();
      conversation.liveUserMessage = null;
    }
  }

  /// 把当前会话挂接到正在运行的聊天流。
  void syncAttachedStream(Conversation conversation) {
    if (chat._disposed ||
        chat.expired ||
        !chat.synchronized ||
        conversation.id != chat.activeId ||
        conversation.submission?.running == true) {
      return;
    }
    final run = chat.activeRun(conversation.id);
    if (run == null || run['source'] != 'chat') return;
    final runId = run['runId'] as String?;
    if (runId == null || runId.isEmpty) return;
    if (conversation.attachedRunId == runId &&
        conversation._attachedStreamApi != null) {
      return;
    }
    detachAttachedStream(
      conversation,
      clearReplies: conversation.attachedRunId != runId,
    );
    final transport = chat.openEvents();
    conversation._attachedStreamApi = transport;
    conversation.attachedRunId = runId;
    unawaited(_listenAttachedStream(conversation, runId, transport));
  }

  Future<void> _listenAttachedStream(
    Conversation conversation,
    String runId,
    MuseApi transport,
  ) async {
    final streamed = <String, String>{};
    bool stillAttached() =>
        chat._owns(conversation) &&
        !chat.expired &&
        identical(conversation._attachedStreamApi, transport) &&
        conversation.attachedRunId == runId;
    try {
      await for (final frame in transport.streamRun(conversation.id, runId)) {
        if (!stillAttached()) return;
        final data = frame.data;
        switch (data['type']) {
          case 'TEXT_MESSAGE_CONTENT':
            final id = data['messageId'] as String;
            final delta = data['delta'] as String;
            final updated = (streamed[id] ?? '') + delta;
            streamed[id] = updated;
            conversation.liveReplies[id] = updated;
            chat._changed();
          case 'CUSTOM':
            _recordAgendaReceipt(conversation, data);
          case 'RUN_FINISHED':
          case 'RUN_ERROR':
            break;
        }
      }
    } catch (error) {
      if (identical(conversation._attachedStreamApi, transport)) {
        chat._checkAuth(error);
      }
    } finally {
      transport.close();
      if (identical(conversation._attachedStreamApi, transport)) {
        conversation._attachedStreamApi = null;
        if (chat._owns(conversation)) {
          unawaited(chat.refresh(conversation));
          chat._changed();
        }
      }
    }
  }

  /// 覆盖当前草稿文本。
  void setDraft(String draft) {
    if (chat.active.canEditDraft) chat.active.draft = draft;
  }

  /// 引用一条消息。
  bool quoteMessage(Conversation conversation, String? binding, String id) {
    if (!identical(conversation, chat.active) ||
        conversation.binding != binding ||
        conversation.missing ||
        !conversation.canEditDraft) {
      return false;
    }
    final message = conversation._savedMessage(id);
    if (message == null || !message.canQuote) return false;
    conversation.quote = MessageQuote._(message);
    chat._changed();
    return true;
  }

  /// 取消引用。
  void removeQuote() {
    if (!chat.active.canEditDraft) return;
    chat.active.quote = null;
    chat._changed();
  }

  /// 取回上一条未发送的草稿。
  void recoverDraft() {
    final conversation = chat.active;
    if (!conversation.canEditDraft || !conversation.hasRecoveredDraft) return;
    final recovered = conversation._recoveredDrafts.removeAt(0);
    if (!conversation._draftIsEmpty) {
      conversation._recoveredDrafts.add(conversation._draft);
    }
    conversation._applyDraft(recovered);
    conversation.error = null;
    conversation.attachmentError = null;
    chat._changed();
  }

  /// 选择草稿附件。
  Future<void> chooseAttachments() async {
    if (!canPickAttachments()) return;
    final conversation = chat.active;
    final binding = conversation.binding;
    _attachmentPickerOwner = conversation;
    conversation.attachmentError = null;
    chat._changed();
    bool stillCurrent() =>
        chat._owns(conversation) &&
        !chat.expired &&
        conversation.binding == binding;
    try {
      final picked = await chat._attachmentPicker(
        maxFiles: maxChatAttachments - conversation.draftAttachments.length,
        maxBytes: maxChatAttachmentBytes - conversation.draftAttachmentBytes,
      );
      if (stillCurrent() && picked.isNotEmpty) {
        conversation.draftAttachments = appendChatAttachments(
          conversation.draftAttachments,
          picked,
          _newId,
        );
      }
    } on AttachmentException catch (error) {
      if (stillCurrent()) conversation.attachmentError = error.message;
    } catch (_) {
      if (stillCurrent()) conversation.attachmentError = '无法打开或读取选中的文件';
    } finally {
      _attachmentPickerOwner = null;
      chat._changed();
    }
  }

  /// 移除草稿附件。
  void removeDraftAttachment(String id) {
    if (pickingAttachments || !chat.active.canEditDraft) return;
    chat.active.draftAttachments = List.unmodifiable(
      chat.active.draftAttachments.where((attachment) => attachment.id != id),
    );
    chat.active.attachmentError = null;
    chat._changed();
  }

  String? _outgoingText(Conversation conversation, _Draft draft) {
    if (draft.text.trim().isEmpty && draft.attachments.isEmpty) return null;
    final text = draft.quote?.compose(draft.text) ?? draft.text;
    if (text.length <= maxChatMessageLength) return text;
    conversation.error = '消息正文（含引用）最多 $maxChatMessageLength 个字符';
    chat._changed();
    return null;
  }

  /// 发送当前草稿。
  Future<void> send() {
    final conversation = chat.active;
    if (!canSend()) return Future.value();
    final draft = conversation._draft;
    final text = _outgoingText(conversation, draft);
    return text == null ? Future.value() : _send(conversation, draft, text);
  }

  Future<void> _send(
    Conversation conversation,
    _Draft draft,
    String text,
  ) async {
    final attachments = draft.attachments;
    final message = ChatMessage(
      _newId(),
      'user',
      text,
      attachments: attachments,
      sentAt: DateTime.now(),
    );
    final pending = Submission(_newId(), message, draft);
    conversation._clearDraft();
    conversation.attachmentError = null;
    conversation.error = null;
    conversation.submission = pending;
    chat._changed();
    try {
      await for (final frame in chat.api.run({
        'sessionId': conversation.id,
        'runId': pending.runId,
        'expectedRevision': conversation.revision,
        'message': {
          'id': message.id,
          'content': text,
          if (attachments.isNotEmpty)
            'attachments': attachments
                .map((attachment) => attachment.toRequest())
                .toList(),
        },
      })) {
        if (!chat._owns(conversation)) return;
        final data = frame.data;
        switch (data['type']) {
          case 'TEXT_MESSAGE_CONTENT':
            final id = data['messageId'] as String;
            final delta = data['delta'] as String;
            pending.replies.update(
              id,
              (text) => text + delta,
              ifAbsent: () => delta,
            );
            chat._changed();
          case 'CUSTOM':
            _recordAgendaReceipt(conversation, data);
          case 'RUN_FINISHED':
            pending._streamTerminal =
                pending._streamTerminal ||
                (data['runId'] == pending.runId &&
                    data['sessionId'] == conversation.id);
          case 'RUN_ERROR':
            // RUN_ERROR 属于本次专用响应流，协议不返回运行 ID。
            pending._streamTerminal = true;
            if (data['code'] != 'STOPPED' && !pending.stopping) {
              conversation.error = '本次回复未完成';
            }
        }
      }
      if (!pending._streamTerminal && !pending.settled) {
        pending.reconciling = true;
      }
    } catch (error) {
      chat._checkAuth(error);
      // 只把服务端明确的前置拒绝视为终态，仍先回读历史再恢复草稿。
      pending.rejection = switch (error) {
        ApiException(status: 413, code: 'REQUEST_TOO_LARGE') =>
          '消息超过服务端大小限制，草稿已恢复',
        ApiException(status: 400, code: 'INVALID_INPUT') => '服务端拒绝了消息内容，草稿已恢复',
        ApiException(status: 409, code: 'HISTORY_CONFLICT') => '会话记录已更新，草稿已恢复',
        _ => null,
      };
      pending.settled = pending.settled || pending.rejection != null;
      if (!pending.settled) {
        pending.reconciling = true;
      }
    } finally {
      pending.running = false;
      pending.stopping = false;
      pending.settled = pending.settled || pending._streamTerminal;
      pending._closed.complete();
      if (chat._owns(conversation) && conversation.submission == pending) {
        if (pending.settled || conversation.waitingToSend) {
          unawaited(chat.refresh(conversation));
        } else if (chat.synchronized) {
          unawaited(reconcileSubmission(conversation));
        }
        chat._changed();
      }
    }
  }

  /// 停止当前运行。
  Future<void> stop() async {
    if (!canStop(sendNext: false)) return;
    final conversation = chat.active;
    final pending = conversation.submission;
    if (pending != null && pending.running) {
      await _requestStop(conversation, pending);
      return;
    }
    final run = chat.activeRun(conversation.id);
    final runId = run?['runId'] as String?;
    if (runId == null) return;
    conversation.stoppingActiveRun = true;
    var confirmed = false;
    chat._changed();
    try {
      final result = await chat.api.post('/api/conversation/stop', {
        'sessionId': conversation.id,
        'runId': runId,
      });
      if (result['stopped'] == true) {
        confirmed = true;
        return;
      }
    } catch (error) {
      chat._checkAuth(error);
    } finally {
      conversation.stoppingActiveRun = false;
      if (!confirmed &&
          chat._owns(conversation) &&
          chat.activeRun(conversation.id)?['runId'] == runId) {
        conversation.error = '停止尚未确认，可稍后再试';
      }
      chat._changed();
    }
  }

  Future<bool> _requestStop(
    Conversation conversation,
    Submission pending,
  ) async {
    pending.stopping = true;
    chat._changed();
    try {
      final result = await chat.api.post('/api/conversation/stop', {
        'sessionId': conversation.id,
        'runId': pending.runId,
      });
      if (result['stopped'] == true) return true;
    } catch (error) {
      chat._checkAuth(error);
    }
    pending.stopping = false;
    if (chat._owns(conversation) &&
        conversation.submission == pending &&
        pending.running) {
      conversation.error = '停止尚未确认，可稍后再试';
    }
    chat._changed();
    return false;
  }

  /// 停止当前运行并发送草稿。
  Future<void> stopAndSend() async {
    if (!canStop(sendNext: true)) return;
    final conversation = chat.active;
    final followUp = _FollowUp(
      conversation.binding,
      conversation.submission!,
      conversation._draft,
    );
    final text = _outgoingText(conversation, followUp.draft);
    if (text == null) return;
    conversation._followUp = followUp;
    conversation.error = null;
    final confirmed = await Future.any<bool>([
      _confirmFollowUp(conversation, followUp),
      followUp.cancelled.future.then((_) => false),
    ]).timeout(_followUpTimeout, onTimeout: () => false);
    if (!_ownsFollowUp(conversation, followUp)) return;
    if (!confirmed || !_canSend(conversation)) {
      cancelFollowUp(conversation);
      chat._changed();
      return;
    }
    clearFollowUp(conversation);
    await _send(conversation, followUp.draft, text);
  }

  Future<bool> _confirmFollowUp(
    Conversation conversation,
    _FollowUp followUp,
  ) async {
    final previous = followUp.previous;
    if (!await _requestStop(conversation, previous)) return false;
    await previous._closed.future;
    if (!_ownsFollowUp(conversation, followUp)) return false;
    final tracked = chat._workspace.tracksRun(conversation.id, previous.runId);
    if (!previous._streamTerminal || tracked) {
      await previous._workspaceTerminal.future;
      if (!_ownsFollowUp(conversation, followUp)) return false;
    }
    // Stop 的回执和两条 SSE 可以乱序。终态确认后重新读取历史和 revision。
    await chat.refresh(conversation);
    return _ownsFollowUp(conversation, followUp) &&
        conversation.history.any(
          (message) => message.id == previous.message.id,
        );
  }

  bool _ownsFollowUp(Conversation conversation, _FollowUp followUp) =>
      chat._owns(conversation) &&
      identical(conversation._followUp, followUp) &&
      conversation.binding == followUp.binding;

  /// 清理等待发送下一条的状态。
  void clearFollowUp(Conversation conversation) {
    final followUp = conversation._followUp;
    conversation._followUp = null;
    followUp?.cancelled.complete();
  }

  /// 取消等待发送下一条，保留草稿。
  void cancelFollowUp(Conversation conversation) {
    if (!conversation.waitingToSend) return;
    clearFollowUp(conversation);
    conversation.error ??= '未自动发送下一条，草稿已保留';
  }

  /// 取消所有会话等待发送下一条的状态。
  void cancelFollowUps() {
    for (final conversation in chat.conversations.values) {
      cancelFollowUp(conversation);
    }
  }

  String _newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
