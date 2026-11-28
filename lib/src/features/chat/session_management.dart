import 'package:material_ui/material_ui.dart';

import '../../network/api.dart';
import 'chat_controller.dart';

enum _SessionAction { rename, delete }

class SessionManagementMenu extends StatelessWidget {
  const SessionManagementMenu({
    super.key,
    required this.chat,
    required this.session,
  });

  final ChatController chat;
  final SessionEntry session;

  @override
  Widget build(BuildContext context) {
    final renaming = chat.pendingSessionTitle(session.id) != null;
    final deleting = chat.pendingSessionDeletion(session.id) != null;
    return PopupMenuButton<_SessionAction>(
      tooltip: '更多操作：${session.title}',
      enabled: chat.synchronized && !chat.sessionChangeBusy(session.id),
      itemBuilder: (_) => [
        if (!deleting)
          PopupMenuItem(
            value: _SessionAction.rename,
            child: Text(renaming ? '核对重命名' : '重命名'),
          ),
        if (!renaming)
          PopupMenuItem(
            value: _SessionAction.delete,
            child: Text(deleting ? '核对删除' : '删除'),
          ),
      ],
      onSelected: (action) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => switch (action) {
          _SessionAction.rename => _RenameDialog(chat: chat, session: session),
          _SessionAction.delete => _DeleteDialog(chat: chat, session: session),
        },
      ),
    );
  }
}

String _sessionError(Object error) => switch (error) {
  ApiException(status: 401) => '连接已失效，请重新连接后再试。',
  ApiException(status: 404) => '会话已不存在。',
  ApiException(code: 'SESSION_JOB_RUNNING') => '会话还有任务正在运行，请等任务结束后再迁移。',
  ApiException(code: 'SESSION_DELETION_IN_PROGRESS') =>
    '已有删除操作，须沿用原来的任务处置方式。请先核对会话列表。',
  ApiException(code: 'SESSION_DELETING') => '会话正在删除，请核对会话列表。',
  _ => '操作未完成，请稍后再试。',
};

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.chat, required this.session});

  final ChatController chat;
  final SessionEntry session;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  ChatController get _chat => widget.chat;
  String get _id => widget.session.id;
  late final _title = TextEditingController(
    text: _chat.pendingSessionTitle(_id) ?? widget.session.title,
  );
  String? _message;

  Future<void> _save({required bool verify}) async {
    try {
      final result = await (verify
          ? _chat.verifySessionChange(_id)
          : _chat.renameSession(_id, _title.text));
      if (!mounted) return;
      if (result == SessionChangeResult.confirmed) {
        Navigator.pop(context);
      } else {
        final saved = _chat.sessionEntry(_id)?.title;
        setState(
          () => _message = switch (result) {
            SessionChangeResult.unknown => '重命名结果未确认，请先核对。',
            _ when saved != null => '服务器当前保存的名称是「$saved」。',
            _ => '会话已不存在。',
          },
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = _sessionError(error));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _chat,
    builder: (context, _) {
      final busy = _chat.sessionChangeBusy(_id);
      final unknown = _chat.pendingSessionTitle(_id) != null;
      final saved = _chat.sessionEntry(_id);
      final title = _title.text.trim();
      final canSave =
          !busy &&
          _chat.synchronized &&
          saved != null &&
          title.isNotEmpty &&
          title != saved.title &&
          title.length <= 200;
      return PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: const Text('重命名会话'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                autofocus: !unknown,
                enabled: !busy && !unknown && saved != null,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: '会话名称',
                  errorText: title.length > 200 ? '会话名称过长' : null,
                ),
                onChanged: (_) => setState(() => _message = null),
                onSubmitted: canSave && !unknown
                    ? (_) => _save(verify: false)
                    : null,
              ),
              if (busy || unknown || _message != null || saved == null)
                _SessionStatus(
                  busy
                      ? '正在连接服务器…'
                      : _message ??
                            (saved == null ? '会话已不存在。' : '重命名结果未确认，请先核对。'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: Text(unknown ? '返回' : '取消'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : unknown
                  ? () => _save(verify: true)
                  : canSave
                  ? () => _save(verify: false)
                  : null,
              child: Text(unknown && !busy ? '核对结果' : '保存'),
            ),
          ],
        ),
      );
    },
  );
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.chat, required this.session});

  final ChatController chat;
  final SessionEntry session;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  ChatController get _chat => widget.chat;
  String get _id => widget.session.id;
  SessionSchedules? _schedules;
  SessionScheduleDisposition? _choice;
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? message}) async {
    setState(() {
      _loading = true;
      _schedules = null;
      _choice = null;
      _message = message;
    });
    try {
      final schedules = await _chat.readSessionSchedules(_id);
      if (mounted) setState(() => _schedules = schedules);
    } catch (error) {
      if (error is ApiException && error.status == 404) {
        await _chat.refreshDirectory();
      }
      if (mounted) {
        setState(
          () => _message = error is ApiException && error.status == 404
              ? '会话已不存在。'
              : '无法读取关联任务和监控，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(
    SessionSchedules schedules,
    SessionScheduleDisposition choice,
  ) async {
    try {
      final result = await _chat.deleteSession(_id, schedules, choice);
      if (!mounted) return;
      if (result == SessionChangeResult.confirmed) {
        Navigator.pop(context);
      } else {
        // 如需继续同一个删除，先重新读取绑定的清单并让用户再次确认。
        setState(() {
          _schedules = null;
          _message = '删除结果未确认，请先核对。';
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.code == 'SESSION_SCHEDULES_CHANGED') {
        await _load(message: '任务或监控已变化，请核对新清单后再确认。');
      } else {
        setState(() => _message = _sessionError(error));
      }
    }
  }

  Future<void> _verify() async {
    final result = await _chat.verifySessionChange(_id);
    if (!mounted) return;
    if (result == SessionChangeResult.confirmed) {
      Navigator.pop(context);
    } else {
      setState(() => _message = '删除结果仍未确认。可以稍后核对，或重新查看清单后继续原操作。');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _chat,
    builder: (context, _) {
      final busy = _chat.sessionChangeBusy(_id);
      final pending = _chat.pendingSessionDeletion(_id);
      final schedules = _schedules;
      final choice =
          pending ??
          (schedules?.isEmpty == true
              ? SessionScheduleDisposition.delete
              : _choice);
      final session = _chat.sessionEntry(_id);
      return PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: const Text('删除会话'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '删除「${session?.title ?? widget.session.title}」会永久移除聊天历史和反馈，并清除该会话的本地草稿。正在生成的回复也会停止。',
              ),
              if (schedules != null && session != null) ...[
                if (schedules.isEmpty) const _SessionStatus('此会话没有关联的定时任务或监控。'),
                for (final title in schedules.jobs)
                  _SessionStatus('定时任务：$title'),
                for (final title in schedules.monitors)
                  _SessionStatus('网页监控：$title'),
                if (!schedules.isEmpty)
                  RadioGroup<SessionScheduleDisposition>(
                    groupValue: choice,
                    onChanged: (value) => setState(() => _choice = value),
                    child: Column(
                      children: [
                        RadioListTile(
                          title: const Text('保留并转到默认会话'),
                          value: SessionScheduleDisposition.moveToMain,
                          enabled: !busy && pending == null,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile(
                          title: const Text('一并删除任务和监控'),
                          value: SessionScheduleDisposition.delete,
                          enabled: !busy && pending == null,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
              ],
              if (_loading || busy || _message != null || session == null)
                _SessionStatus(
                  _loading
                      ? '正在读取关联任务和监控…'
                      : busy
                      ? '正在连接服务器…'
                      : _message ?? '会话已不存在。',
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: Text(session == null ? '关闭' : '取消'),
            ),
            if (!busy && pending != null)
              TextButton(
                onPressed: _loading ? null : _verify,
                child: const Text('核对结果'),
              ),
            if (!_loading && session != null && schedules == null)
              TextButton(
                onPressed: busy ? null : _load,
                child: Text(pending == null ? '重读清单' : '查看清单'),
              ),
            if (session != null && schedules != null)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: busy || !_chat.synchronized || choice == null
                    ? null
                    : () => _delete(schedules, choice),
                child: Text(pending == null ? '删除会话' : '继续删除'),
              ),
          ],
        ),
      );
    },
  );
}

class _SessionStatus extends StatelessWidget {
  const _SessionStatus(this.message);

  final String message;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(top: 8), child: Text(message));
}
