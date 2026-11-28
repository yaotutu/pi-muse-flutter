import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../../network/api.dart';
import '../../shared/agenda_receipt.dart';
import '../../shared/workspace_events.dart';
import 'approval.dart';
import 'chat_attachment.dart';
import 'session.dart';
import 'visible_text.dart';

export 'approval.dart';
export 'session.dart';

part 'chat_message.dart';
part 'conversation.dart';
part 'workspace_flow.dart';
part 'session_flow.dart';
part 'draft_flow.dart';
part 'message_feedback.dart';

/// 打开日程里的某个事项。第二个参数为真时直接定位到时间设置。
typedef AgendaItemOpener = void Function(String itemId, bool focusTime);

/// 聊天状态控制器。
///
/// 每个服务连接只有一条 `/api/events` 通知流，聊天 AG-UI SSE 按运行单独管理。
/// 控制器持有会话目录、历史、草稿、运行与审批的本地状态，内部职责拆成
/// 工作区通知与运行、会话目录与历史、草稿与运行流程三部分。
class ChatController extends ChangeNotifier {
  ChatController(
    this.api,
    this.openEvents, {
    ChatAttachmentPicker attachmentPicker = pickAndroidChatAttachments,
  }) : _attachmentPicker = attachmentPicker {
    _workspace = _WorkspaceFlow(this);
    _sessions = _SessionFlow(this);
    _draft = _DraftFlow(this);
  }

  final MuseApi api;
  final MuseApi Function() openEvents;
  final ChatAttachmentPicker _attachmentPicker;

  /// 工作区通知、运行与审批。
  late final _WorkspaceFlow _workspace;

  /// 会话目录与历史读取。
  late final _SessionFlow _sessions;

  /// 草稿与运行流程。
  late final _DraftFlow _draft;

  /// 各会话的本地状态，按会话 ID 隔离。
  final conversations = <String, Conversation>{
    mainSession: Conversation(mainSession),
  };

  /// 待用户确认的审批。
  final approvals = <String, Approval>{};

  /// 会话目录。
  List<SessionEntry> sessions = const [SessionEntry(mainSession, '主聊天')];

  /// 会话目录读取失败时的提示。
  String? directoryError;

  /// 当前会话。
  String activeId = mainSession;

  /// 通知流是否已就绪。
  bool synchronized = false;

  /// 连接是否已失效。
  bool expired = false;

  bool _disposed = false;

  /// 工作区快照版本，ready 时递增。
  int get workspaceSnapshot => _workspace.snapshot;

  /// 连接级通知事件。
  ///
  /// 每个连接只有一条 `/api/events`，其它功能按事件名订阅同一条流，不另开连接。
  Stream<WorkspaceEvent> get workspaceEvents => _workspace.events;

  /// 当前会话。
  Conversation get active => conversations[activeId]!;

  /// 附件选择器是否被当前会话占用。
  bool get pickingAttachments => _draft.pickingAttachments;

  /// 是否可以继续添加附件。
  bool get canPickAttachments => _draft.canPickAttachments();

  /// 当前会话是否可发送。
  bool get canSend => _draft.canSend();

  /// 是否可以停止当前运行。
  bool canStop({required bool sendNext}) => _draft.canStop(sendNext: sendNext);

  /// 会话是否允许修改消息反馈。
  bool canChangeFeedback(Conversation conversation) =>
      _owns(conversation) &&
      synchronized &&
      !expired &&
      !conversation.missing &&
      pendingSessionDeletion(conversation.id) == null;

  /// 顶部的运行状态文案。
  String? get activityLabel => _draft.activityLabel();

  /// 当前会话的待确认审批。
  List<Approval> get activeApprovals => _workspace.sessionApprovals(activeId);

  /// 指定会话的待确认审批。
  List<Approval> sessionApprovals(String id) => _workspace.sessionApprovals(id);

  /// 聊天页展示的审批，含最近已结算的卡片。
  List<Approval> chatApprovals(String sessionId) =>
      _workspace.chatApprovals(sessionId);

  /// 指定会话正在运行的执行记录。
  Json? activeRun(String id) => _workspace.activeRun(id);

  /// 消息关联的执行记录。
  Json? runForMessage(String id, ChatMessage message) =>
      _workspace.runForMessage(id, message);

  /// 执行步骤列表。
  List<Json> stepsOf(Json? run) => _workspace.stepsOf(run);

  /// 指定会话的执行记录。
  List<Json> executionRuns(String id) => _workspace.executionRuns(id);

  /// 执行历史的版本号，用于判断是否需要重新读取。
  (int, int) executionHistoryVersion(String id, {required bool approvals}) =>
      _workspace.executionHistoryVersion(id, approvals: approvals);

  /// 审批决定是否需要用户核对。
  bool approvalNeedsVerification(String id) =>
      _workspace.approvalNeedsVerification(id);

  /// 审批的版本号。
  int approvalRevision(String id) => _workspace.approvalRevision(id);

  /// 读取执行详情。
  Future<Json> readExecution(String path, {Map<String, String>? query}) =>
      _workspace.readExecution(path, query: query);

  /// 读取审批详情。
  Future<Approval> readApprovalDetail(String sessionId, String id) =>
      _workspace.readApprovalDetail(sessionId, id);

  /// 提交审批决定。
  Future<Approval> decide(Approval approval, bool approve) =>
      _workspace.decide(approval, approve);

  /// 核对审批结果。
  Future<Approval> checkApproval(Approval approval) =>
      _workspace.checkApproval(approval);

  /// 订阅通知并同步当前会话。
  void start() => _workspace.start();

  /// 重新建立通知订阅。
  void reconnect() => _workspace.reconnect();

  /// 应用回到前台时对齐历史与在途流。
  void onAppResumed(Duration? backgroundDuration) =>
      _workspace.onAppResumed(backgroundDuration);

  /// 刷新会话目录。
  Future<bool> refreshDirectory() => _sessions.refreshDirectory();

  /// 会话目录条目。
  SessionEntry? sessionEntry(String id) => _sessions.sessionEntry(id);

  /// 会话变更是否正在进行。
  bool sessionChangeBusy(String id) => _sessions.sessionChangeBusy(id);

  /// 待确认的会话标题。
  String? pendingSessionTitle(String id) => _sessions.pendingSessionTitle(id);

  /// 待确认的会话删除处置方式。
  SessionScheduleDisposition? pendingSessionDeletion(String id) =>
      _sessions.pendingSessionDeletion(id);

  /// 读取会话关联的任务与监控。
  Future<SessionSchedules> readSessionSchedules(String id) =>
      _sessions.readSessionSchedules(id);

  /// 重命名会话。
  Future<SessionChangeResult> renameSession(String id, String input) =>
      _sessions.renameSession(id, input);

  /// 删除会话。
  Future<SessionChangeResult> deleteSession(
    String id,
    SessionSchedules schedules,
    SessionScheduleDisposition disposition,
  ) => _sessions.deleteSession(id, schedules, disposition);

  /// 核对上一次会话变更的结果。
  Future<SessionChangeResult> verifySessionChange(String id) =>
      _sessions.verifySessionChange(id);

  /// 切换当前会话。
  void select(String id) => _sessions.select(id);

  /// 新建会话。
  Future<void> createSession(String title) => _sessions.createSession(title);

  /// 刷新会话历史。
  Future<void> refresh(Conversation conversation) =>
      _sessions.refresh(conversation);

  /// 核对当前会话的发送结果。
  Future<void> verifySubmission() => _draft.verifySubmission();

  /// 修改消息评价。
  Future<void> changeReaction(
    Conversation conversation,
    String binding,
    String id,
    MessageReaction selection,
  ) => _changeFeedback(conversation, binding, id, selection: selection);

  /// 修改消息收藏状态。
  Future<void> changeSaved(
    Conversation conversation,
    String binding,
    String id,
    bool saved,
  ) => _changeFeedback(conversation, binding, id, saved: saved);

  /// 核对消息反馈。
  Future<void> verifyFeedback(
    Conversation conversation,
    String binding,
    String id,
  ) => _changeFeedback(conversation, binding, id);

  /// 覆盖当前草稿文本。
  void setDraft(String draft) => _draft.setDraft(draft);

  /// 引用一条消息。
  bool quoteMessage(Conversation conversation, String? binding, String id) =>
      _draft.quoteMessage(conversation, binding, id);

  /// 取消引用。
  void removeQuote() => _draft.removeQuote();

  /// 取回上一条未发送的草稿。
  void recoverDraft() => _draft.recoverDraft();

  /// 选择草稿附件。
  Future<void> chooseAttachments() => _draft.chooseAttachments();

  /// 移除草稿附件。
  void removeDraftAttachment(String id) => _draft.removeDraftAttachment(id);

  /// 发送当前草稿。
  Future<void> send() => _draft.send();

  /// 停止当前运行。
  Future<void> stop() => _draft.stop();

  /// 停止当前运行并发送草稿。
  Future<void> stopAndSend() => _draft.stopAndSend();

  /// 会话是否仍由本控制器持有。
  bool _owns(Conversation conversation) =>
      !_disposed && identical(conversations[conversation.id], conversation);

  /// 鉴权失败时收敛本地状态。
  void _checkAuth(Object error) {
    if (error is ApiException && error.status == 401 && !_disposed) {
      expired = true;
      synchronized = false;
      _draft.cancelFollowUps();
      for (final conversation in conversations.values) {
        conversation._feedbackRequests.clear();
      }
      _workspace.closeNotifications();
    }
  }

  /// 通知界面刷新。
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _draft.cancelFollowUps();
    for (final conversation in conversations.values) {
      _draft.detachAttachedStream(conversation, clearReplies: true);
    }
    _workspace.dispose();
    api.close();
    super.dispose();
  }
}
