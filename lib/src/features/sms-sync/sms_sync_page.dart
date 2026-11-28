import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../network/api.dart';
import 'sms_history_section.dart';
import 'sms_sync.dart';
import '../subagents/subagents_client.dart';

class SmsSyncPage extends StatefulWidget {
  const SmsSyncPage({super.key, this.api, required this.connectionUsesHttp});

  final MuseApi? api;
  final bool connectionUsesHttp;

  @override
  State<SmsSyncPage> createState() => _SmsSyncPageState();
}

class _SmsSyncPageState extends State<SmsSyncPage> with WidgetsBindingObserver {
  static const _disclosure = '开启后，新收到的短信原文和发件人会发送到已连接的 Pi Muse 服务器。';
  static const _httpDisclosure = '当前使用 HTTP，短信和连接令牌在传输时未加密。';
  static const _permissionHelp =
      '在应用设置的「权限 → 短信」中授权。若 Android 提示权限受限，请先在应用信息右上角菜单点「允许受限设置」，再授权或返回这里重试。';

  Map<String, Object?>? _status;
  late final Timer _poll;
  bool _busy = false;
  bool _reading = false;
  bool _refreshAfterRead = false;
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
    if (state == AppLifecycleState.resumed) _refresh(requestFresh: true);
  }

  Future<void> _refresh({bool requestFresh = false}) async {
    if (_reading) {
      _refreshAfterRead |= requestFresh;
      return;
    }
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
      if (_refreshAfterRead && mounted) {
        _refreshAfterRead = false;
        unawaited(_refresh());
      }
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
      await SmsSync.setEnabled(enabled);
      if (widget.api case final api? when enabled) {
        try {
          await SubagentsClient(api).setEnabled('sms', true);
        } catch (_) {
          // 本机开关已保存，服务端收到短信时可自行开启对应子代理。
        }
      }
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    String errorMessage = '无法更新本机短信同步，请重试',
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = errorMessage);
    } finally {
      if (mounted) {
        await _refresh();
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Widget _infoRow(IconData icon, String title, String subtitle, {Color? tone}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = tone ?? scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: tone ?? scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final enabled = status?['enabled'] == true;
    final permission = status?['permission'] == true;
    final needsPermission = status != null && !permission;
    final pending = status?['pending'] as int? ?? 0;
    final failed = status?['failed'] as int? ?? 0;
    final checking = status?['checking'] as int? ?? 0;
    final canRetry = status?['canRetry'] as int? ?? 0;
    final lastSuccess = status?['lastSuccess'] as int? ?? 0;
    final block = status?['status'];
    final actionRequired = switch (block) {
      'auth' => '连接已失效，请在设置中重新连接服务器。',
      'connection' => '无法读取服务器连接，请在设置中重新连接。',
      'paused' => '短信已保存在本机。服务器恢复接收后点「立即同步」。',
      'local_error' => '本机短信同步遇到错误，请重试。',
      _ => null,
    };
    final waiting = switch (block) {
      'network' => '服务器暂时不可达，等待重试。',
      _ => '等待网络或服务器确认。',
    };
    final urgent =
        enabled &&
        permission &&
        (block == 'auth' || block == 'connection' || block == 'local_error');
    final summary = !enabled
        ? '本机同步已关闭。'
        : !permission
        ? '需要 Android 短信权限。'
        : actionRequired ??
              (pending > failed + canRetry
                  ? waiting
                  : pending == 0
                  ? '正在等待新短信。收到后会自动上传，可查看「上次确认成功」。'
                  : '有短信需要处理。');
    final canSync =
        enabled &&
        permission &&
        !_busy &&
        pending > failed &&
        block != 'auth' &&
        block != 'connection';
    final localizations = MaterialLocalizations.of(context);
    final successTime = DateTime.fromMillisecondsSinceEpoch(lastSuccess);
    final scheme = Theme.of(context).colorScheme;
    final caption = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: const Text('短信同步')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '新短信同步',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('同步新短信'),
                    subtitle: const Text('仅同步开启后收到的新短信'),
                    value: enabled,
                    onChanged: _busy || status == null ? null : _change,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _disclosure,
                          style: caption?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (widget.connectionUsesHttp) ...[
                          const SizedBox(height: 4),
                          Text(
                            _httpDisclosure,
                            style: caption?.copyWith(color: scheme.error),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  if (status == null && _error == null)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    if (status != null)
                      _infoRow(
                        Icons.outbox_outlined,
                        '待同步 $pending 条',
                        summary,
                        tone: urgent ? scheme.error : null,
                      ),
                    if (needsPermission)
                      _infoRow(
                        Icons.gpp_maybe_outlined,
                        'Android 尚未授予短信权限',
                        _permissionHelp,
                      ),
                    if (failed > 0)
                      _infoRow(
                        Icons.error_outline,
                        '$failed 条未能同步',
                        '与服务器记录冲突或格式不符，已保留在本机。',
                        tone: scheme.error,
                      ),
                    if (checking > 0)
                      _infoRow(
                        Icons.hourglass_top,
                        '$checking 条正在核对入队结果',
                        '正在向服务器确认是否已接收。',
                      ),
                    if (canRetry > 0)
                      _infoRow(
                        Icons.search_off,
                        '$canRetry 条等待重试',
                        '尚未在服务器找到，可点下方「立即同步」重试。',
                      ),
                    if (lastSuccess > 0)
                      _infoRow(
                        Icons.cloud_done_outlined,
                        '上次确认成功',
                        '${localizations.formatCompactDate(successTime)} '
                            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(successTime))}',
                      ),
                    if (_error case final error?)
                      _infoRow(
                        Icons.error_outline,
                        '出错了',
                        error,
                        tone: scheme.error,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (enabled && !permission)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _change(true),
                              icon: const Icon(Icons.gpp_maybe_outlined),
                              label: const Text('重新授权短信权限'),
                            ),
                          if (needsPermission)
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      SmsSync.openAppSettings,
                                      errorMessage:
                                          '无法打开 Android 应用设置，请从系统设置进入',
                                    ),
                              icon: const Icon(Icons.settings_outlined),
                              label: const Text('打开应用设置'),
                            )
                          else
                            FilledButton.tonalIcon(
                              onPressed: canSync
                                  ? () => _run(SmsSync.retry)
                                  : null,
                              icon: const Icon(Icons.sync),
                              label: const Text('立即同步'),
                            ),
                          if (_busy) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  SmsHistorySection(
                    connectionUsesHttp: widget.connectionUsesHttp,
                    permissionHelp: _permissionHelp,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
