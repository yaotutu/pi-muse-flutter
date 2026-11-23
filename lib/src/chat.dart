import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'chat_attachment.dart';

const mainSession = 'main';

class ChatMessage {
  const ChatMessage(
    this.id,
    this.role,
    this.text, {
    this.attachments = const [],
    this.sentAt,
  });

  factory ChatMessage.fromJson(Json json) {
    final metadata = json['metadata'];
    final createdAt = metadata is Json ? metadata['createdAt'] : null;
    return ChatMessage(
      json['id'] as String,
      json['role'] as String,
      json['content'] as String? ?? '',
      sentAt: createdAt is String ? DateTime.tryParse(createdAt) : null,
      attachments:
          (json['attachments'] as List?)
              ?.cast<Json>()
              .map(ChatAttachment.fromJson)
              .toList(growable: false) ??
          const [],
    );
  }

  final String id;
  final String role;
  final String text;
  final List<ChatAttachment> attachments;
  final DateTime? sentAt;
}

class SessionEntry {
  const SessionEntry(this.id, this.title);

  factory SessionEntry.fromJson(Json json) =>
      SessionEntry(json['id'] as String, json['title'] as String);

  final String id;
  final String title;
}

enum SessionScheduleDisposition {
  delete('delete'),
  moveToMain('move-to-main');

  const SessionScheduleDisposition(this.value);
  final String value;
}

class SessionSchedules {
  SessionSchedules.fromJson(Json json)
    : revision = json['scheduleRevision'] as String,
      jobs = _titles(json['jobs']),
      monitors = _titles(json['monitors']) {
    if (!_validRevision.hasMatch(revision)) throw const FormatException();
  }

  static final _validRevision = RegExp(r'^[a-f0-9]{64}$');
  static List<String> _titles(Object? items) => List.unmodifiable(
    (items as List).cast<Json>().map((entry) => entry['title'] as String),
  );

  final String revision;
  final List<String> jobs;
  final List<String> monitors;

  bool get isEmpty => jobs.isEmpty && monitors.isEmpty;
}

enum SessionChangeResult { confirmed, differentTitle, unknown }

typedef _SessionChange = ({
  String? title,
  SessionScheduleDisposition? disposition,
});

class Approval {
  Approval.fromJson(Json json)
    : id = json['id'] as String,
      sessionId = json['sessionId'] as String?,
      revision = json['revision'] as int,
      status = json['status'] as String,
      scope = (json['preview'] as Json)['scope'] as String,
      path = (json['preview'] as Json)['path'] as String,
      before = (json['preview'] as Json)['before'] as String,
      after = (json['preview'] as Json)['after'] as String,
      beforeExists = (json['preview'] as Json)['beforeExists'] as bool,
      expiresAt = DateTime.parse(json['expiresAt'] as String);

  final String id;
  final String? sessionId;
  final int revision;
  final String status;
  final String scope;
  final String path;
  final String before;
  final String after;
  final bool beforeExists;
  final DateTime expiresAt;
}

class Submission {
  Submission(this.runId, this.message, this.attachments);

  final String runId;
  final ChatMessage message;
  final List<DraftAttachment> attachments;
  final replies = <String, String>{};
  String? rejection;
  bool running = true;
  bool stopping = false;
  bool settled = false;
  bool verifying = false;

  Iterable<ChatMessage> get overlay sync* {
    yield message;
    for (final reply in replies.entries) {
      yield ChatMessage(reply.key, 'assistant', reply.value);
    }
  }
}

class Conversation {
  Conversation(this.id);

  final String id;
  String draft = '';
  List<DraftAttachment> draftAttachments = const [];
  String? attachmentError;
  String? revision;

  int get draftAttachmentBytes =>
      draftAttachments.fold(0, (bytes, attachment) => bytes + attachment.size);
  String? binding;
  List<ChatMessage> history = const [];
  Submission? submission;
  String? error;
  String? historyError;
  bool missing = false;
  bool dirty = true;
  Future<void>? read;

  Iterable<ChatMessage> get messages sync* {
    yield* history;
    final pending = submission;
    if (pending != null) yield* pending.overlay;
  }
}

class ChatController extends ChangeNotifier {
  ChatController(
    this.api,
    this.openEvents, {
    ChatAttachmentPicker attachmentPicker = pickAndroidChatAttachments,
  }) : _attachmentPicker = attachmentPicker;

  final MuseApi api;
  final MuseApi Function() openEvents;
  final ChatAttachmentPicker _attachmentPicker;
  Conversation? _attachmentPickerOwner;
  final conversations = <String, Conversation>{
    mainSession: Conversation(mainSession),
  };
  final approvals = <String, Approval>{};
  final _unconfirmedApprovals = <String>{};
  final _approvalRevisions = <String, int>{};

  bool approvalNeedsVerification(String id) =>
      _unconfirmedApprovals.contains(id);
  final _runs = <(String, String), Json>{};
  final _runRevisions = <(String, String), int>{};
  final _random = Random.secure();
  List<SessionEntry> sessions = const [SessionEntry(mainSession, '主聊天')];
  String activeId = mainSession;
  String? directoryError;
  bool synchronized = false;
  bool expired = false;
  bool _disposed = false;
  bool _directoryDirty = false;
  Future<bool>? _directoryRead;
  final _sessionChanges = <String, _SessionChange>{};
  final _busySessionChanges = <String>{};
  MuseApi? _notificationApi;
  Timer? _reconnect;
  int _retry = 0;
  String? _instanceId;

  Conversation get active => conversations[activeId]!;
  List<Approval> get activeApprovals => approvals.values
      .where((approval) => approval.sessionId == activeId)
      .toList();

  bool get pickingAttachments => identical(_attachmentPickerOwner, active);

  bool get canPickAttachments =>
      _attachmentPickerOwner == null &&
      !expired &&
      !active.missing &&
      pendingSessionDeletion(activeId) == null &&
      active.binding != null &&
      active.submission == null &&
      active.draftAttachments.length < maxChatAttachments &&
      active.draftAttachmentBytes < maxChatAttachmentBytes;

  bool get canSend =>
      !pickingAttachments &&
      synchronized &&
      !expired &&
      !active.missing &&
      pendingSessionDeletion(activeId) == null &&
      active.revision != null &&
      !active.dirty &&
      active.read == null &&
      active.historyError == null &&
      active.submission == null &&
      !_runs.values.any((run) => run['sessionId'] == activeId);

  String? get activityLabel {
    final pending = active.submission;
    if (pending?.stopping == true) return '正在停止';
    if (!synchronized) return null;
    final run = _runs.values
        .where((run) => run['sessionId'] == activeId)
        .firstOrNull;
    if (run != null) {
      final label = run['label'] as String?;
      return label?.isNotEmpty == true ? label! : '正在处理';
    }
    if (pending?.running != true) return null;
    return pending!.replies.isEmpty ? '正在处理' : '正在回复';
  }

  void start() {
    reconnect();
    unawaited(refresh(active));
  }

  void reconnect() {
    if (_disposed || expired) return;
    _reconnect?.cancel();
    _notificationApi?.close();
    synchronized = false;
    final transport = openEvents();
    _notificationApi = transport;
    _changed();
    unawaited(_listen(transport));
  }

  Future<void> _listen(MuseApi transport) async {
    try {
      await for (final frame in transport.events()) {
        if (_notificationApi != transport) return;
        _applyWorkspaceEvent(frame);
      }
    } catch (error) {
      if (_notificationApi == transport) _checkAuth(error);
    } finally {
      transport.close();
      if (_notificationApi == transport) {
        _notificationApi = null;
        synchronized = false;
        _changed();
        if (!_disposed && !expired) {
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
      _instanceId = data['instanceId'] as String;
      _runs.clear();
      _runRevisions.clear();
      approvals.clear();
      for (final run in running) {
        _recordRun(run);
      }
      for (final approval in pending) {
        _recordApproval(approval, snapshot: true);
      }
      _retry = 0;
      synchronized = true;
      unawaited(refreshDirectory());
      for (final conversation in conversations.values) {
        unawaited(refresh(conversation));
      }
    } else if (synchronized && data['instanceId'] == _instanceId) {
      switch (frame.event) {
        case 'session_status_updated':
          _recordRun(data);
        case 'approval_pending':
          _recordApproval(Approval.fromJson(data));
        case 'approval_updated':
          _finishApproval(data['id'] as String, data['revision'] as int);
        case 'conversation_updated':
          final conversation = conversations[data['sessionId']];
          if (conversation != null) unawaited(refresh(conversation));
        case 'session_directory_updated':
          unawaited(refreshDirectory());
      }
    }
    _changed();
  }

  void _recordRun(Json run) {
    final key = (run['sessionId'] as String, run['runId'] as String);
    final revision = run['revision'] as int;
    if (revision <= (_runRevisions[key] ?? 0)) return;
    _runRevisions[key] = revision;
    if (run['status'] == 'running') {
      _runs[key] = run;
    } else {
      _runs.remove(key);
      final conversation = conversations[key.$1];
      final pending = conversation?.submission;
      if (conversation != null && pending?.runId == key.$2) {
        pending!.settled = true;
        unawaited(refresh(conversation));
      }
    }
  }

  void _recordApproval(Approval approval, {bool snapshot = false}) {
    final known = _approvalRevisions[approval.id] ?? 0;
    if (approval.revision < known ||
        (!snapshot && approval.revision == known)) {
      return;
    }
    _approvalRevisions[approval.id] = approval.revision;
    if (approval.status == 'pending') approvals[approval.id] = approval;
  }

  void _finishApproval(String id, int revision) {
    if (revision <= (_approvalRevisions[id] ?? 0)) return;
    _approvalRevisions[id] = revision;
    _unconfirmedApprovals.remove(id);
    approvals.remove(id);
  }

  Future<bool> refreshDirectory() {
    _directoryDirty = true;
    return _directoryRead ??= _readDirectory();
  }

  Future<bool> _readDirectory() async {
    try {
      do {
        _directoryDirty = false;
        final data = await api.get('/api/sessions');
        if (_disposed) return false;
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
        sessions = entries;
        directoryError = null;
        final knownIds = {...conversations.keys, ..._sessionChanges.keys};
        for (final id in knownIds.where((id) => !ids.contains(id))) {
          _forgetSession(id);
        }
      } while (_directoryDirty);
      return true;
    } catch (error) {
      _checkAuth(error);
      directoryError = '读取会话失败，点此重试';
      return false;
    } finally {
      _directoryRead = null;
      _changed();
    }
  }

  SessionEntry? sessionEntry(String id) =>
      sessions.where((session) => session.id == id).firstOrNull;

  bool sessionChangeBusy(String id) => _busySessionChanges.contains(id);

  String? pendingSessionTitle(String id) => _sessionChanges[id]?.title;

  SessionScheduleDisposition? pendingSessionDeletion(String id) =>
      _sessionChanges[id]?.disposition;

  String _sessionPath(String id) => '/api/sessions/${Uri.encodeComponent(id)}';

  Future<SessionSchedules> readSessionSchedules(String id) async {
    try {
      final data = await api.get('${_sessionPath(id)}/schedules');
      return SessionSchedules.fromJson(data);
    } catch (error) {
      _checkAuth(error);
      _changed();
      rethrow;
    }
  }

  Future<SessionChangeResult> renameSession(String id, String input) {
    final title = input.trim();
    if (title.isEmpty || title.length > 200) {
      throw const FormatException('Invalid session title');
    }
    return _submitSessionChange(
      id,
      (title: title, disposition: null),
      () async {
        final data = await api.patch(_sessionPath(id), {'title': title});
        final entry = SessionEntry.fromJson(data['session'] as Json);
        if (entry.id != id || entry.title != title) {
          throw const FormatException();
        }
        if (_disposed) return;
        sessions = sessions.map((row) => row.id == id ? entry : row).toList();
      },
    );
  }

  Future<SessionChangeResult> deleteSession(
    String id,
    SessionSchedules schedules,
    SessionScheduleDisposition disposition,
  ) => _submitSessionChange(
    id,
    (title: null, disposition: disposition),
    () async {
      final data = await api.delete(_sessionPath(id), {
        'scheduleRevision': schedules.revision,
        'scheduleDisposition': disposition.value,
      });
      if (data['ok'] != true || (data['removed'] as Json)['sessions'] != 1) {
        throw const FormatException();
      }
      if (_disposed) return;
      sessions = sessions.where((row) => row.id != id).toList();
      _forgetSession(id);
    },
  );

  Future<SessionChangeResult> _submitSessionChange(
    String id,
    _SessionChange change,
    Future<void> Function() submit,
  ) async {
    final previous = _sessionChanges[id];
    if (_disposed ||
        expired ||
        !synchronized ||
        id == mainSession ||
        sessionEntry(id) == null ||
        sessionChangeBusy(id) ||
        (previous != null &&
            (previous.disposition == null ||
                previous.disposition != change.disposition))) {
      throw const FormatException('Session change is not available');
    }
    _sessionChanges[id] = change;
    _busySessionChanges.add(id);
    _changed();
    try {
      await submit();
      _sessionChanges.remove(id);
      if (!_disposed) unawaited(refreshDirectory());
      return SessionChangeResult.confirmed;
    } catch (error) {
      _checkAuth(error);
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
      _changed();
    }
  }

  Future<SessionChangeResult> verifySessionChange(String id) async {
    final change = _sessionChanges[id];
    if (change == null || !_busySessionChanges.add(id)) {
      return SessionChangeResult.unknown;
    }
    _changed();
    try {
      return await _verifySessionChange(id, change);
    } finally {
      _busySessionChanges.remove(id);
      _changed();
    }
  }

  Future<SessionChangeResult> _verifySessionChange(
    String id,
    _SessionChange change,
  ) async {
    if (_disposed || !await refreshDirectory()) {
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
    conversations.remove(id);
    _runs.removeWhere((key, _) => key.$1 == id);
    approvals.removeWhere((_, approval) => approval.sessionId == id);
    if (activeId == id) select(mainSession);
  }

  bool _owns(Conversation conversation) =>
      !_disposed && identical(conversations[conversation.id], conversation);

  void select(String id) {
    if (id == activeId) return;
    activeId = id;
    conversations.putIfAbsent(id, () => Conversation(id));
    unawaited(refresh(active));
    _changed();
  }

  Future<void> createSession(String title) async {
    final response = await api.post('/api/sessions', {'title': title});
    if (_disposed) return;
    final entry = SessionEntry.fromJson(response['session'] as Json);
    sessions = [...sessions, entry];
    select(entry.id);
    unawaited(refreshDirectory());
  }

  Future<void> refresh(Conversation conversation) {
    if (!_owns(conversation)) return Future.value();
    conversation.dirty = true;
    if (conversation.submission?.running == true) return Future.value();
    return conversation.read ??= _readHistory(conversation);
  }

  Future<void> _readHistory(Conversation conversation) async {
    try {
      do {
        conversation.dirty = false;
        final data = await api.get(
          '/api/conversation',
          query: {'sessionId': conversation.id},
        );
        if (!_owns(conversation)) return;
        if (conversation.dirty) continue;
        if (data['sessionId'] != conversation.id) throw const FormatException();
        final binding = data['piSessionId'] as String?;
        if (binding == null && conversation.id != mainSession) {
          // 删除途中可能先失去历史绑定，等目录确认后再丢弃本地草稿。
          conversation.missing = true;
          if (pendingSessionDeletion(conversation.id) == null) {
            unawaited(refreshDirectory());
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
          if (saved || bindingChanged || binding == null) {
            conversation.submission = null;
          } else if (pending.settled) {
            conversation.draft = pending.message.text;
            conversation.draftAttachments = pending.attachments;
            conversation.error = pending.rejection ?? '服务器未保存这条消息，草稿已恢复';
            conversation.submission = null;
          }
        }
        if (bindingChanged) {
          conversation.draft = '';
          conversation.draftAttachments = const [];
          conversation.attachmentError = null;
          conversation.error = null;
        }
        conversation.binding = binding;
        conversation.missing = binding == null;
        conversation.revision = data['revision'] as String;
        conversation.history = history;
        conversation.historyError = null;
      } while (conversation.dirty && conversation.submission?.running != true);
    } catch (error) {
      _checkAuth(error);
      conversation.historyError = '消息同步失败，点此重新核对';
    } finally {
      conversation.read = null;
      _changed();
    }
  }

  Future<void> verifySubmission() async {
    final conversation = active;
    final pending = conversation.submission;
    if (pending == null || pending.running || pending.verifying) return;
    pending.verifying = true;
    _changed();
    try {
      final response = await api.get(
        '/api/runs/status',
        query: {'sessionId': conversation.id, 'runId': pending.runId},
      );
      final status = response['status'];
      if (status is Json &&
          const [
            'succeeded',
            'failed',
            'cancelled',
          ].contains(status['status'])) {
        pending.settled = true;
      }
    } catch (error) {
      _checkAuth(error);
      if (error is ApiException && error.status == 404 && synchronized) {
        pending.settled = true;
      }
    } finally {
      pending.verifying = false;
      if (!_disposed) await refresh(conversation);
    }
  }

  void setDraft(String draft) => active.draft = draft;

  Future<void> chooseAttachments() async {
    if (!canPickAttachments) return;
    final conversation = active;
    final binding = conversation.binding;
    _attachmentPickerOwner = conversation;
    conversation.attachmentError = null;
    _changed();
    bool stillCurrent() =>
        _owns(conversation) && !expired && conversation.binding == binding;
    try {
      final picked = await _attachmentPicker(
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
      _changed();
    }
  }

  void removeDraftAttachment(String id) {
    if (pickingAttachments || active.submission != null) return;
    active.draftAttachments = List.unmodifiable(
      active.draftAttachments.where((attachment) => attachment.id != id),
    );
    active.attachmentError = null;
    _changed();
  }

  Future<void> send() async {
    final conversation = active;
    final text = conversation.draft;
    final attachments = conversation.draftAttachments;
    if (!canSend || (text.trim().isEmpty && attachments.isEmpty)) return;
    final message = ChatMessage(
      _newId(),
      'user',
      text,
      attachments: attachments,
      sentAt: DateTime.now(),
    );
    final pending = Submission(_newId(), message, attachments);
    conversation.draft = '';
    conversation.draftAttachments = const [];
    conversation.attachmentError = null;
    conversation.error = null;
    conversation.submission = pending;
    _changed();
    var finished = false;
    try {
      await for (final frame in api.run({
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
        if (!_owns(conversation)) return;
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
            _changed();
          case 'RUN_FINISHED':
            finished = true;
          case 'RUN_ERROR':
            finished = true;
            if (data['code'] != 'STOPPED' && !pending.stopping) {
              conversation.error = '本次回复未完成';
            }
        }
      }
      if (!finished) conversation.error = '回复连接中断，正在核对发送结果';
    } catch (error) {
      _checkAuth(error);
      // 只把服务端明确的前置拒绝视为终态，仍先回读历史再恢复草稿。
      pending.rejection = switch (error) {
        ApiException(status: 413, code: 'REQUEST_TOO_LARGE') =>
          '消息超过服务端大小限制，草稿已恢复',
        ApiException(status: 400, code: 'INVALID_INPUT') => '服务端拒绝了消息内容，草稿已恢复',
        ApiException(status: 409, code: 'HISTORY_CONFLICT') => '会话记录已更新，草稿已恢复',
        _ => null,
      };
      pending.settled = pending.settled || pending.rejection != null;
      conversation.error = '消息发送遇到问题，正在核对服务器记录';
    } finally {
      if (_owns(conversation)) {
        pending.running = false;
        pending.stopping = false;
        pending.settled = pending.settled || finished;
        unawaited(refresh(conversation));
        _changed();
      }
    }
  }

  Future<void> stop() async {
    final conversation = active;
    final pending = conversation.submission;
    if (pending == null || !pending.running || pending.stopping) return;
    pending.stopping = true;
    _changed();
    try {
      final result = await api.post('/api/conversation/stop', {
        'sessionId': conversation.id,
        'runId': pending.runId,
      });
      if (result['stopped'] != true && pending.running) {
        pending.stopping = false;
        conversation.error = '停止尚未确认，可稍后再试';
      }
    } catch (error) {
      _checkAuth(error);
      pending.stopping = false;
      if (conversation.submission == pending) {
        conversation.error = '停止尚未确认，可稍后再试';
      }
    }
    _changed();
  }

  Future<String> decide(Approval approval, bool approve) async {
    if (!synchronized ||
        approvals[approval.id]?.revision != approval.revision ||
        approvalNeedsVerification(approval.id) ||
        !approval.expiresAt.isAfter(DateTime.now())) {
      throw const FormatException('Approval is no longer actionable');
    }
    _unconfirmedApprovals.add(approval.id);
    try {
      final result = await api.post(
        '/api/approvals/${Uri.encodeComponent(approval.id)}/decision',
        {'decision': approve ? 'approve' : 'deny'},
      );
      return _applyApprovalResult(result);
    } catch (error) {
      _checkAuth(error);
      _changed();
      rethrow;
    }
  }

  Future<String> checkApproval(Approval approval) async {
    try {
      final result = await api.get(
        '/api/approvals/${Uri.encodeComponent(approval.id)}',
      );
      return _applyApprovalResult(result);
    } catch (error) {
      _checkAuth(error);
      _changed();
      rethrow;
    }
  }

  String _applyApprovalResult(Json result) {
    final payload = result['approval'] as Json? ?? result;
    final approval = Approval.fromJson(payload);
    _unconfirmedApprovals.remove(approval.id);
    if (approval.status != 'pending') {
      _finishApproval(approval.id, approval.revision);
    }
    _changed();
    return approval.status;
  }

  String _newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  void _checkAuth(Object error) {
    if (error is ApiException && error.status == 401 && !_disposed) {
      expired = true;
      synchronized = false;
      _notificationApi?.close();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    final transport = _notificationApi;
    _notificationApi = null;
    transport?.close();
    api.close();
    super.dispose();
  }
}
