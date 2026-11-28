import 'package:material_ui/material_ui.dart';

import 'chat_controller.dart';
import 'session_management.dart';

class SessionPanel extends StatelessWidget {
  const SessionPanel({
    super.key,
    required this.chat,
    required this.onWorkspaceFiles,
    this.onSessionOpened,
    this.onSettings,
  });

  final ChatController chat;
  final VoidCallback onWorkspaceFiles;
  final VoidCallback? onSessionOpened;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: chat,
    builder: (context, _) => _buildPanel(context),
  );

  Widget _buildPanel(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
            child: FilledButton.tonalIcon(
              onPressed: chat.synchronized
                  ? () async {
                      final created = await showDialog<bool>(
                        context: context,
                        builder: (_) => _NewSessionDialog(chat: chat),
                      );
                      if (created == true && context.mounted) {
                        onSessionOpened?.call();
                      }
                    }
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('新建会话'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (chat.directoryError case final String error)
                  ListTile(title: Text(error), onTap: chat.refreshDirectory),
                for (final session in chat.sessions)
                  ListTile(
                    key: ValueKey(session.id),
                    shape: const StadiumBorder(),
                    title: Text(
                      session.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    leading: Icon(
                      session.id == mainSession
                          ? Icons.home_outlined
                          : Icons.chat_bubble_outline,
                    ),
                    selected: session.id == chat.activeId,
                    selectedColor: colors.onSecondaryContainer,
                    selectedTileColor: colors.secondaryContainer,
                    trailing: session.id == mainSession
                        ? null
                        : SessionManagementMenu(chat: chat, session: session),
                    onTap: () {
                      if (chat.sessionEntry(session.id) == null) return;
                      chat.select(session.id);
                      onSessionOpened?.call();
                    },
                  ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('工作区文件'),
            enabled: !chat.expired,
            onTap: chat.expired ? null : onWorkspaceFiles,
          ),
          if (onSettings != null)
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: onSettings,
            ),
        ],
      ),
    );
  }
}

class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog({required this.chat});

  final ChatController chat;

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  final _title = TextEditingController();
  bool _working = false;
  bool _unknown = false;

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty || _working || _unknown) return;
    setState(() => _working = true);
    try {
      await widget.chat.createSession(title);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      await widget.chat.refreshDirectory();
      if (mounted) {
        setState(() {
          _working = false;
          _unknown = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: AlertDialog(
      title: const Text('新建会话'),
      content: _unknown
          ? const Text('新建结果未确认。请返回会话列表核对。')
          : TextField(
              controller: _title,
              autofocus: true,
              enabled: !_working,
              maxLength: 200,
              decoration: const InputDecoration(hintText: '会话名称'),
              onSubmitted: (_) => _create(),
              onChanged: (_) => setState(() {}),
            ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: Text(_unknown ? '返回会话列表' : '取消'),
        ),
        if (!_unknown)
          FilledButton(
            onPressed: !_working && _title.text.trim().isNotEmpty
                ? _create
                : null,
            child: const Text('创建'),
          ),
      ],
    ),
  );
}
