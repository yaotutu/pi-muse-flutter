import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import 'api.dart';
import 'chat_attachment.dart';
import 'visible_text.dart';

const mainSession = 'main';
const maxChatMessageLength = 32000;
const _followUpTimeout = Duration(seconds: 15);

enum MessageReaction { like, dislike }

enum ReactionRequestState { busy, unconfirmed }

MessageReaction? _readReaction(Json feedback) => switch (feedback['reaction']) {
  'like' => MessageReaction.like,
  'dislike' => MessageReaction.dislike,
  null when feedback.containsKey('reaction') => null,
  _ => throw const FormatException('Invalid message reaction'),
};

class ChatMessage {
  const ChatMessage(
    this.id,
    this.role,
    this.text, {
    this.attachments = const [],
    this.sentAt,
    this.source,
    this.feedbackAvailable = false,
    this.reaction,
  });

  factory ChatMessage.fromJson(Json json) {
    final metadata = json['metadata'] as Json?;
    final createdAt = metadata?['createdAt'];
    final feedback = json['feedback'];
    final feedbackAvailable =
        metadata?['feedbackAvailable'] == true && feedback is Json;
    return ChatMessage(
      json['id'] as String,
      json['role'] as String,
      json['content'] as String? ?? '',
      sentAt: createdAt is String ? DateTime.tryParse(createdAt) : null,
      source: metadata?['source'] as String?,
      feedbackAvailable: feedbackAvailable,
      reaction: feedbackAvailable ? _readReaction(feedback) : null,
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
  final String? source;
  final bool feedbackAvailable;
  final MessageReaction? reaction;

  String get visibleText =>
      role == 'assistant' ? visibleAssistantText(text) : text;
  bool get canQuote =>
      (source == null || source == 'chat') &&
      (role == 'user' || role == 'assistant') &&
      visibleText.trim().isNotEmpty;

  ChatMessage _withReaction(MessageReaction? value) => ChatMessage(
    id,
    role,
    text,
    attachments: attachments,
    sentAt: sentAt,
    source: source,
    feedbackAvailable: feedbackAvailable,
    reaction: value,
  );
}

class MessageQuote {
  MessageQuote._(ChatMessage message)
    : label = message.role == 'assistant' ? '助手回复' : '我的消息',
      excerpt = _quoteExcerpt(message.visibleText.trim());

  static String _quoteExcerpt(String text) {
    var end = 0;
    for (final character in text.characters.take(1200)) {
      if (end + character.length > 4800) break;
      end += character.length;
    }
    return end == text.length ? text : '${text.substring(0, end)}…';
  }

  final String label;
  final String excerpt;

  String compose(String text) {
    final lines = const LineSplitter().convert(excerpt);
    return '> $label\n${lines.map((line) => '> $line').join('\n')}\n\n$text';
  }
}

typedef _Draft = ({
  String text,
  MessageQuote? quote,
  List<DraftAttachment> attachments,
});

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
      title = json['title'] as String?,
      execution = json['execution'] as Json?,
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
  final String? title;
  final Json? execution;
  final String scope;
  final String path;
  final String before;
  final String after;
  final bool beforeExists;
  final DateTime expiresAt;
}

class Submission {
  Submission(this.runId, this.message, this._draft);

  final String runId;
  final ChatMessage message;
  final _Draft _draft;
  final _closed = Completer<void>();
  final _workspaceTerminal = Completer<void>();
  bool _streamTerminal = false;
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

class _FollowUp {
  _FollowUp(this.binding, this.previous, this.draft);

  final String? binding;
  final Submission previous;
  final _Draft draft;
  final cancelled = Completer<void>();
}

class Conversation {
  Conversation(this.id);

  final String id;
  String draft = '';
  List<DraftAttachment> draftAttachments = const [];
  MessageQuote? quote;
  final _recoveredDrafts = <_Draft>[];
  final _reactions = <String, ReactionRequestState>{};
  _FollowUp? _followUp;

  bool get waitingToSend => _followUp != null;
  bool get canEditDraft => !waitingToSend && (submission?.running ?? true);
  bool get hasRecoveredDraft => _recoveredDrafts.isNotEmpty;
  ReactionRequestState? reactionState(String id) => _reactions[id];

  _Draft get _draft =>
      (text: draft, quote: quote, attachments: draftAttachments);
  bool get _draftIsEmpty =>
      draft.isEmpty && quote == null && draftAttachments.isEmpty;

  void _applyDraft(_Draft value) {
    draft = value.text;
    quote = value.quote;
    draftAttachments = value.attachments;
  }

  void _clearDraft() {
    draft = '';
    quote = null;
    draftAttachments = const [];
  }

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
  final _lastRuns = <String, Json>{};
  final _activityChanges = <String, int>{};
  final _approvalChanges = <String, int>{};
  int _workspaceSnapshot = 0;

  int get workspaceSnapshot => _workspaceSnapshot;
  int approvalRevision(String id) => _approvalRevisions[id] ?? 0;

  (int, int) executionHistoryVersion(String id, {required bool approvals}) => (
    _workspaceSnapshot,
    (approvals ? _approvalChanges : _activityChanges)[id] ?? 0,
  );

  List<Json> executionRuns(String id) {
    if (!synchronized) return const [];
    final active = _runs.entries
        .where((entry) => entry.key.$1 == id)
        .map((entry) => entry.value)
        .toList();
    final last = _lastRuns[id];
    if (active.isEmpty && last != null) active.add(last);
    return active;
  }

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
  List<Approval> get activeApprovals => sessionApprovals(activeId);

  List<Approval> sessionApprovals(String id) =>
      approvals.values.where((approval) => approval.sessionId == id).toList();

  bool get pickingAttachments => identical(_attachmentPickerOwner, active);

  bool get canPickAttachments =>
      _attachmentPickerOwner == null &&
      !expired &&
      !active.missing &&
      pendingSessionDeletion(activeId) == null &&
      active.binding != null &&
      active.canEditDraft &&
      active.draftAttachments.length < maxChatAttachments &&
      active.draftAttachmentBytes < maxChatAttachmentBytes;

  bool get canSend => !active.waitingToSend && _canSend(active);

  bool canReact(Conversation conversation) =>
      _owns(conversation) &&
      synchronized &&
      !expired &&
      !conversation.missing &&
      pendingSessionDeletion(conversation.id) == null;

  bool canStop({required bool sendNext}) {
    final conversation = active;
    final pending = conversation.submission;
    return !expired &&
        pending?.running == true &&
        !pending!.stopping &&
        !conversation.waitingToSend &&
        (!sendNext ||
            (synchronized &&
                !pickingAttachments &&
                conversation.binding != null &&
                pendingSessionDeletion(conversation.id) == null));
  }

  bool _canSend(Conversation conversation) =>
      _owns(conversation) &&
      !identical(_attachmentPickerOwner, conversation) &&
      synchronized &&
      !expired &&
      !conversation.missing &&
      pendingSessionDeletion(conversation.id) == null &&
      conversation.revision != null &&
      !conversation.dirty &&
      conversation.read == null &&
      conversation.historyError == null &&
      conversation.submission == null &&
      !_runs.keys.any((key) => key.$1 == conversation.id);

  String? get activityLabel {
    final pending = active.submission;
    if (active.waitingToSend) return '正在停止并准备发送';
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
    _cancelFollowUps();
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
        _cancelFollowUps();
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
      final instanceId = data['instanceId'] as String;
      final sameInstance = _instanceId == instanceId;
      final previouslyRunning = sameInstance
          ? _runs.keys.toList()
          : const <(String, String)>[];
      if (!sameInstance) {
        _cancelFollowUps();
        _lastRuns.clear();
        _activityChanges.clear();
        _approvalChanges.clear();
      }
      _instanceId = instanceId;
      final snapshot = ++_workspaceSnapshot;
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
      for (final key in previouslyRunning) {
        if (!_runs.containsKey(key)) unawaited(_readMissedRun(key, snapshot));
      }
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
          _finishApproval(
            data['id'] as String,
            data['revision'] as int,
            data['sessionId'] as String?,
          );
        case 'activity_updated':
          final id = data['sessionId'] as String;
          _activityChanges.update(id, (value) => value + 1, ifAbsent: () => 1);
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
    } else if (_isTerminalStatus(run['status'])) {
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
      final conversation = conversations[key.$1];
      if (conversation == null) return;
      final pending =
          conversation.submission ?? conversation._followUp?.previous;
      final isLocalRun = pending?.runId == key.$2;
      if (isLocalRun) {
        pending!.settled = true;
        if (!pending._workspaceTerminal.isCompleted) {
          pending._workspaceTerminal.complete();
        }
      }
      if (wasRunning || isLocalRun) unawaited(refresh(conversation));
    }
  }

  Future<void> _readMissedRun((String, String) key, int snapshot) async {
    try {
      final response = await api.get(
        '/api/runs/status',
        query: {'sessionId': key.$1, 'runId': key.$2},
      );
      final run = response['status'] as Json;
      if (_disposed ||
          !synchronized ||
          snapshot != _workspaceSnapshot ||
          response['instanceId'] != _instanceId ||
          run['sessionId'] != key.$1 ||
          run['runId'] != key.$2 ||
          !_isTerminalStatus(run['status']) ||
          sessionEntry(key.$1) == null) {
        return;
      }
      _recordRun(run);
      _changed();
    } catch (error) {
      if (snapshot != _workspaceSnapshot || !synchronized) return;
      _checkAuth(error);
      if (expired) _changed();
    }
  }

  bool _isTerminalStatus(Object? status) =>
      status == 'succeeded' || status == 'failed' || status == 'cancelled';

  void _recordApproval(Approval approval, {bool snapshot = false}) {
    final known = _approvalRevisions[approval.id] ?? 0;
    if (approval.revision < known ||
        (!snapshot && approval.revision == known)) {
      return;
    }
    _approvalRevisions[approval.id] = approval.revision;
    if (approval.status == 'pending') approvals[approval.id] = approval;
  }

  void _finishApproval(String id, int revision, String? sessionId) {
    if (revision <= (_approvalRevisions[id] ?? 0)) return;
    _approvalRevisions[id] = revision;
    _unconfirmedApprovals.remove(id);
    final session = sessionId ?? approvals[id]?.sessionId;
    approvals.remove(id);
    if (session != null) {
      _approvalChanges.update(session, (value) => value + 1, ifAbsent: () => 1);
    }
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
    final conversation = conversations[id];
    if (change.disposition != null && conversation != null) {
      _cancelFollowUp(conversation);
    }
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
    final removed = conversations.remove(id);
    if (removed != null) _clearFollowUp(removed);
    _runs.removeWhere((key, _) => key.$1 == id);
    _lastRuns.remove(id);
    _activityChanges.remove(id);
    _approvalChanges.remove(id);
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
          _clearFollowUp(conversation);
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
          _clearFollowUp(conversation);
          conversation._clearDraft();
          conversation._recoveredDrafts.clear();
          conversation._reactions.clear();
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
    if (pending == null ||
        pending.running ||
        pending.verifying ||
        conversation.waitingToSend) {
      return;
    }
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

  ChatMessage? _savedMessage(Conversation conversation, String id) =>
      conversation.history.where((message) => message.id == id).firstOrNull;

  Future<void> changeReaction(
    Conversation conversation,
    String binding,
    String id,
    MessageReaction? selection,
  ) async {
    final message = _savedMessage(conversation, id);
    final state = conversation.reactionState(id);
    final verifying = selection == null;
    if (!canReact(conversation) ||
        conversation.binding != binding ||
        message == null ||
        !message.feedbackAvailable ||
        (verifying
            ? state != ReactionRequestState.unconfirmed
            : state != null)) {
      return;
    }
    final path =
        '${_sessionPath(conversation.id)}/messages/${Uri.encodeComponent(id)}/feedback';
    bool stillCurrent() =>
        _owns(conversation) &&
        !conversation.missing &&
        conversation.binding == binding &&
        !expired;
    conversation._reactions[id] = ReactionRequestState.busy;
    _changed();
    try {
      final response = selection == null
          ? await api.get(path, query: {'piSessionId': binding})
          : await api.put('$path/reaction', {
              'piSessionId': binding,
              'reaction': selection == message.reaction ? null : selection.name,
            });
      if (response['comments'] is! List) throw const FormatException();
      final reaction = _readReaction(response);
      if (!stillCurrent() || expired) return;
      // 丢弃写入前已开始的历史读取，避免旧反应重新覆盖按钮。
      if (conversation.read != null) conversation.dirty = true;
      conversation.history = [
        for (final saved in conversation.history)
          saved.id == id ? saved._withReaction(reaction) : saved,
      ];
      conversation._reactions.remove(id);
    } catch (error) {
      _checkAuth(error);
      if (!stillCurrent()) return;
      if (error is ApiException &&
          (error.status == 404 || error.status == 409)) {
        conversation._reactions.remove(id);
        unawaited(refresh(conversation));
      } else if (verifying ||
          error is! ApiException ||
          error.status == 0 ||
          error.status == 408 ||
          error.status >= 500) {
        conversation._reactions[id] = ReactionRequestState.unconfirmed;
      } else {
        conversation._reactions.remove(id);
      }
      rethrow;
    } finally {
      _changed();
    }
  }

  void setDraft(String draft) {
    if (active.canEditDraft) active.draft = draft;
  }

  bool quoteMessage(Conversation conversation, String? binding, String id) {
    if (!identical(conversation, active) ||
        conversation.binding != binding ||
        conversation.missing ||
        !conversation.canEditDraft) {
      return false;
    }
    final message = _savedMessage(conversation, id);
    if (message == null || !message.canQuote) return false;
    conversation.quote = MessageQuote._(message);
    _changed();
    return true;
  }

  void removeQuote() {
    if (!active.canEditDraft) return;
    active.quote = null;
    _changed();
  }

  void recoverDraft() {
    final conversation = active;
    if (!conversation.canEditDraft || !conversation.hasRecoveredDraft) return;
    final recovered = conversation._recoveredDrafts.removeAt(0);
    if (!conversation._draftIsEmpty) {
      conversation._recoveredDrafts.add(conversation._draft);
    }
    conversation._applyDraft(recovered);
    conversation.error = null;
    conversation.attachmentError = null;
    _changed();
  }

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
    if (pickingAttachments || !active.canEditDraft) return;
    active.draftAttachments = List.unmodifiable(
      active.draftAttachments.where((attachment) => attachment.id != id),
    );
    active.attachmentError = null;
    _changed();
  }

  String? _outgoingText(Conversation conversation, _Draft draft) {
    if (draft.text.trim().isEmpty && draft.attachments.isEmpty) return null;
    final text = draft.quote?.compose(draft.text) ?? draft.text;
    if (text.length <= maxChatMessageLength) return text;
    conversation.error = '消息正文（含引用）最多 $maxChatMessageLength 个字符';
    _changed();
    return null;
  }

  Future<void> send() {
    final conversation = active;
    if (!canSend) return Future.value();
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
    _changed();
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
        conversation.error = '回复连接中断，正在核对发送结果';
      }
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
      pending.running = false;
      pending.stopping = false;
      pending.settled = pending.settled || pending._streamTerminal;
      pending._closed.complete();
      if (_owns(conversation) && conversation.submission == pending) {
        unawaited(refresh(conversation));
        _changed();
      }
    }
  }

  Future<void> stop() async {
    if (!canStop(sendNext: false)) return;
    await _requestStop(active, active.submission!);
  }

  Future<bool> _requestStop(
    Conversation conversation,
    Submission pending,
  ) async {
    pending.stopping = true;
    _changed();
    try {
      final result = await api.post('/api/conversation/stop', {
        'sessionId': conversation.id,
        'runId': pending.runId,
      });
      if (result['stopped'] == true) return true;
    } catch (error) {
      _checkAuth(error);
    }
    pending.stopping = false;
    if (_owns(conversation) &&
        conversation.submission == pending &&
        pending.running) {
      conversation.error = '停止尚未确认，可稍后再试';
    }
    _changed();
    return false;
  }

  Future<void> stopAndSend() async {
    if (!canStop(sendNext: true)) return;
    final conversation = active;
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
      _cancelFollowUp(conversation);
      _changed();
      return;
    }
    _clearFollowUp(conversation);
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
    final tracked = _runs.containsKey((conversation.id, previous.runId));
    if (!previous._streamTerminal || tracked) {
      await previous._workspaceTerminal.future;
      if (!_ownsFollowUp(conversation, followUp)) return false;
    }
    // Stop 的回执和两条 SSE 可以乱序。终态确认后重新读取历史和 revision。
    await refresh(conversation);
    return _ownsFollowUp(conversation, followUp) &&
        conversation.history.any(
          (message) => message.id == previous.message.id,
        );
  }

  bool _ownsFollowUp(Conversation conversation, _FollowUp followUp) =>
      _owns(conversation) &&
      identical(conversation._followUp, followUp) &&
      conversation.binding == followUp.binding;

  void _clearFollowUp(Conversation conversation) {
    final followUp = conversation._followUp;
    conversation._followUp = null;
    followUp?.cancelled.complete();
  }

  void _cancelFollowUp(Conversation conversation) {
    if (!conversation.waitingToSend) return;
    _clearFollowUp(conversation);
    conversation.error ??= '未自动发送下一条，草稿已保留';
  }

  void _cancelFollowUps() {
    for (final conversation in conversations.values) {
      _cancelFollowUp(conversation);
    }
  }

  Future<Json> readExecution(String path, {Map<String, String>? query}) async {
    try {
      return await api.get(path, query: query);
    } catch (error) {
      _checkAuth(error);
      if (expired) _changed();
      rethrow;
    }
  }

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

  Future<Approval> decide(Approval approval, bool approve) async {
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
      return _applyApprovalResult(result, approval);
    } catch (error) {
      _checkAuth(error);
      _changed();
      rethrow;
    }
  }

  Future<Approval> checkApproval(Approval approval) async {
    try {
      final result = await api.get(
        '/api/approvals/${Uri.encodeComponent(approval.id)}',
      );
      return _applyApprovalResult(result, approval);
    } catch (error) {
      _checkAuth(error);
      _changed();
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
      _finishApproval(approval.id, approval.revision, approval.sessionId);
    }
    _changed();
    return approval;
  }

  String _newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  void _checkAuth(Object error) {
    if (error is ApiException && error.status == 401 && !_disposed) {
      expired = true;
      synchronized = false;
      _cancelFollowUps();
      for (final conversation in conversations.values) {
        conversation._reactions.clear();
      }
      _notificationApi?.close();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelFollowUps();
    _reconnect?.cancel();
    final transport = _notificationApi;
    _notificationApi = null;
    transport?.close();
    api.close();
    super.dispose();
  }
}
