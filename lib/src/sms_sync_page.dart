import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'sms_sync.dart';

class SmsSyncPage extends StatefulWidget {
  const SmsSyncPage({super.key, required this.connectionUsesHttp});

  final bool connectionUsesHttp;

  @override
  State<SmsSyncPage> createState() => _SmsSyncPageState();
}

class _SmsSyncPageState extends State<SmsSyncPage> with WidgetsBindingObserver {
  static const _disclosure = '开启后，新收到的短信原文和发件人会发送到已连接的 Pi Muse 服务器。';
  static const _httpDisclosure = '当前使用 HTTP，短信和连接令牌在传输时未加密。';

  Map<String, Object?>? _status;
  late final Timer _poll;
  bool _busy = false;
  bool _reading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_busy && TickerMode.valuesOf(context).enabled) _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _refresh();
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final status = await SmsSync.status();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted && _status == null) {
        setState(() => _error = '无法读取本机短信同步状态');
      }
    } finally {
      _reading = false;
    }
  }

  Future<void> _change(bool enabled) async {
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('开启短信同步？'),
          content: Text(
            widget.connectionUsesHttp
                ? '$_disclosure\n\n$_httpDisclosure'
                : _disclosure,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _run(() async {
      if (!await SmsSync.setEnabled(enabled) && mounted) {
        setState(() => _error = '请在 Android 应用权限中允许接收短信');
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = '无法更新本机短信同步，请重试');
    } finally {
      if (mounted) {
        await _refresh();
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final enabled = status?['enabled'] == true;
    final permission = status?['permission'] == true;
    final pending = status?['pending'] as int? ?? 0;
    final failed = status?['failed'] as int? ?? 0;
    final checking = status?['checking'] as int? ?? 0;
    final canRetry = status?['canRetry'] as int? ?? 0;
    final lastSuccess = status?['lastSuccess'] as int? ?? 0;
    final actionRequired = switch (status?['status']) {
      'auth' => '连接已失效，请在设置中重新连接服务器。',
      'connection' => '无法读取服务器连接，请在设置中重新连接。',
      'disabled' => '服务器已关闭短信处理。启用后可点「立即同步」。',
      'paused' => '服务器已暂停接收。恢复后可点「立即同步」。',
      'local_error' => '本机短信同步遇到错误，请重试。',
      _ => null,
    };
    final waiting = switch (status?['status']) {
      'network' => '服务器暂时不可达，等待重试。',
      _ => '等待网络或服务器确认。',
    };
    final localizations = MaterialLocalizations.of(context);
    final successTime = DateTime.fromMillisecondsSinceEpoch(lastSuccess);
    return Scaffold(
      appBar: AppBar(title: const Text('短信同步')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                SwitchListTile(
                  title: const Text('同步新短信'),
                  subtitle: const Text(_disclosure),
                  value: enabled,
                  onChanged: _busy || status == null ? null : _change,
                ),
                if (status != null)
                  ListTile(
                    title: Text('待同步 $pending 条'),
                    subtitle: Text(
                      !enabled
                          ? '本机同步已关闭。'
                          : !permission
                          ? '需要 Android 短信权限。'
                          : actionRequired ??
                                (pending > failed + canRetry
                                    ? waiting
                                    : pending == 0
                                    ? '当前没有待同步短信。'
                                    : '有短信需要处理。'),
                    ),
                  ),
                if (failed > 0)
                  ListTile(subtitle: Text('$failed 条与服务器记录冲突或格式不符，已保留在本机。')),
                if (checking > 0)
                  ListTile(subtitle: Text('$checking 条正在核对是否已入队。')),
                if (canRetry > 0)
                  ListTile(subtitle: Text('$canRetry 条尚未在服务器找到，可点「立即同步」重试。')),
                if (lastSuccess > 0)
                  ListTile(
                    subtitle: Text(
                      '上次同步成功 ${localizations.formatCompactDate(successTime)} '
                      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(successTime))}',
                    ),
                  ),
                if (_error case final error?)
                  ListTile(
                    subtitle: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (enabled && !permission)
                  ListTile(
                    title: const Text('重新授权'),
                    onTap: _busy ? null : () => _change(true),
                  ),
                if (enabled && permission)
                  ListTile(
                    title: const Text('立即同步'),
                    leading: const Icon(Icons.sync),
                    enabled:
                        !_busy &&
                        pending > failed &&
                        status?['status'] != 'auth' &&
                        status?['status'] != 'connection',
                    onTap: () => _run(SmsSync.retry),
                  ),
                if (_busy || (status == null && _error == null))
                  const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
