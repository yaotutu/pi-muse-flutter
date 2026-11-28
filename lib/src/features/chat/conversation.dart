part of 'chat_controller.dart';

/// 草稿快照：正文、引用与附件一起保存，发送失败后可以原样恢复。
typedef _Draft = ({
  String text,
  MessageQuote? quote,
  List<DraftAttachment> attachments,
});

/// 停止当前运行后自动发送下一条草稿的中间状态。
class _FollowUp {
  _FollowUp(this.binding, this.previous, this.draft);

  final String? binding;
  final Submission previous;
  final _Draft draft;
  final cancelled = Completer<void>();
}

/// 一次发送的跟踪状态。
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
  bool reconciling = false;
  bool verifying = false;

  Iterable<ChatMessage> get overlay sync* {
    yield message;
    for (final reply in replies.entries) {
      yield ChatMessage(reply.key, 'assistant', reply.value);
    }
  }
}

/// 单个会话的本地状态。
class Conversation {
  Conversation(this.id);

  final String id;
  String draft = '';
  List<DraftAttachment> draftAttachments = const [];
  MessageQuote? quote;
  final _recoveredDrafts = <_Draft>[];
  final _feedbackRequests = <String, FeedbackRequestState>{};
  _FollowUp? _followUp;

  bool get waitingToSend => _followUp != null;
  bool get canEditDraft => !waitingToSend && (submission?.running ?? true);
  bool get hasRecoveredDraft => _recoveredDrafts.isNotEmpty;
  FeedbackRequestState? feedbackState(String id) => _feedbackRequests[id];

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
  Json? lastRun;
  final runsById = <String, Json>{};
  String? attachedRunId;
  ChatMessage? liveUserMessage;
  final liveReplies = <String, String>{};
  MuseApi? _attachedStreamApi;
  bool stoppingActiveRun = false;
  String? error;
  String? historyError;
  bool missing = false;
  bool dirty = true;
  Future<void>? read;

  ChatMessage? _savedMessage(String id) =>
      history.where((message) => message.id == id).firstOrNull;

  Iterable<ChatMessage> get messages sync* {
    yield* history;
    final pending = submission;
    if (pending != null) {
      yield* pending.overlay;
      return;
    }
    final liveUser = liveUserMessage;
    if (liveUser != null &&
        !history.any((message) => message.id == liveUser.id)) {
      yield liveUser;
    }
    if (liveReplies.isNotEmpty) {
      final savedIds = history.map((message) => message.id).toSet();
      for (final reply in liveReplies.entries) {
        if (!savedIds.contains(reply.key)) {
          yield ChatMessage(reply.key, 'assistant', reply.value);
        }
      }
    }
  }
}
