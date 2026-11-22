import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api.dart';

const mainSession = 'main';

class ChatMessage {
  const ChatMessage(this.id, this.role, this.text);

  factory ChatMessage.fromJson(Json json) {
    return ChatMessage(
      json['id'] as String,
      json['role'] as String,
      json['content'] as String? ?? '',
    );
  }

  final String id;
  final String role;
  final String text;
}

class SessionEntry {
  const SessionEntry(this.id, this.title);

  factory SessionEntry.fromJson(Json json) =>
      SessionEntry(json['id'] as String, json['title'] as String);

  final String id;
  final String title;
}

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
  Submission(this.runId, this.message);

  final String runId;
  final ChatMessage message;
  final replies = <String, String>{};
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
  String? revision;
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
  ChatController(this.api, this.openEvents);

  final MuseApi api;
  final MuseApi Function() openEvents;
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
  Future<void>? _directoryRead;
  MuseApi? _notificationApi;
  Timer? _reconnect;
  int _retry = 0;
  String? _instanceId;

  Conversation get active => conversations[activeId]!;
  List<Approval> get activeApprovals => approvals.values
      .where((approval) => approval.sessionId == activeId)
      .toList();

  bool get canSend =>
      synchronized &&
      !expired &&
      !active.missing &&
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

  Future<void> refreshDirectory() {
    _directoryDirty = true;
    return _directoryRead ??= _readDirectory();
  }

  Future<void> _readDirectory() async {
    try {
      do {
        _directoryDirty = false;
        final data = await api.get('/api/sessions');
        if (_disposed) return;
        sessions = (data['sessions'] as List)
            .cast<Json>()
            .map(SessionEntry.fromJson)
            .toList();
        directoryError = null;
      } while (_directoryDirty);
    } catch (error) {
      _checkAuth(error);
      directoryError = '读取会话失败，点此重试';
    } finally {
      _directoryRead = null;
      _changed();
    }
  }

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
        if (_disposed) return;
        if (conversation.dirty) continue;
        if (data['sessionId'] != conversation.id) throw const FormatException();
        final binding = data['piSessionId'] as String?;
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
            conversation.error = '服务器未保存这条消息，内容已放回输入框';
            conversation.submission = null;
          }
        }
        if (bindingChanged) {
          conversation.draft = '';
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

  Future<void> send() async {
    final conversation = active;
    final text = conversation.draft;
    if (!canSend || text.trim().isEmpty) return;
    final message = ChatMessage(_newId(), 'user', text);
    final pending = Submission(_newId(), message);
    conversation.draft = '';
    conversation.error = null;
    conversation.submission = pending;
    _changed();
    var finished = false;
    try {
      await for (final frame in api.run({
        'sessionId': conversation.id,
        'runId': pending.runId,
        'expectedRevision': conversation.revision,
        'message': {'id': message.id, 'content': text},
      })) {
        if (_disposed) return;
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
      conversation.error = '消息发送遇到问题，正在核对服务器记录';
    } finally {
      if (!_disposed) {
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
