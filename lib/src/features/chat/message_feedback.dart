part of 'chat_controller.dart';

/// 消息反馈按会话历史绑定，并在结果不明时只读核对。
extension _MessageFeedback on ChatController {
  Future<void> _changeFeedback(
    Conversation conversation,
    String binding,
    String id, {
    MessageReaction? selection,
    bool? saved,
  }) async {
    final message = conversation._savedMessage(id);
    final state = conversation.feedbackState(id);
    final verifying = selection == null && saved == null;
    if (!canChangeFeedback(conversation) ||
        conversation.binding != binding ||
        message == null ||
        !message.feedbackAvailable ||
        (verifying
            ? state != FeedbackRequestState.unconfirmed
            : state != null)) {
      return;
    }
    final path =
        '${_sessions.sessionPath(conversation.id)}/messages/${Uri.encodeComponent(id)}/feedback';
    bool stillCurrent() =>
        _owns(conversation) &&
        !conversation.missing &&
        conversation.binding == binding &&
        !expired;
    conversation._feedbackRequests[id] = FeedbackRequestState.busy;
    _changed();
    try {
      final Json response;
      if (saved != null) {
        response = await api.put('$path/saved', {
          'piSessionId': binding,
          'saved': saved,
        });
      } else if (selection != null) {
        response = await api.put('$path/reaction', {
          'piSessionId': binding,
          'reaction': selection == message.reaction ? null : selection.name,
        });
      } else {
        response = await api.get(path, query: {'piSessionId': binding});
      }
      if (!stillCurrent()) return;
      if (response['comments'] is! List) throw const FormatException();
      final reaction = _readReaction(response);
      final confirmedSaved = _readSaved(response);
      // 丢弃反馈确认前已开始的历史读取，避免旧反馈重新覆盖按钮。
      if (conversation.read != null) conversation.dirty = true;
      conversation.history = [
        for (final item in conversation.history)
          item.id == id ? item._withFeedback(reaction, confirmedSaved) : item,
      ];
      conversation._feedbackRequests.remove(id);
    } catch (error) {
      _checkAuth(error);
      if (!stillCurrent()) return;
      if (error is ApiException &&
          (error.status == 404 || error.status == 409)) {
        await refresh(conversation);
        if (stillCurrent()) conversation._feedbackRequests.remove(id);
      } else if (verifying ||
          error is! ApiException ||
          error.status == 0 ||
          error.status == 408 ||
          error.status >= 500) {
        conversation._feedbackRequests[id] = FeedbackRequestState.unconfirmed;
      } else {
        conversation._feedbackRequests.remove(id);
      }
      rethrow;
    } finally {
      _changed();
    }
  }
}
