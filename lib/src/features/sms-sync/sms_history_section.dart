import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'sms_sync.dart';

class SmsHistorySection extends StatefulWidget {
  const SmsHistorySection({
    super.key,
    required this.connectionUsesHttp,
    required this.permissionHelp,
  });

  final bool connectionUsesHttp;
  final String permissionHelp;

  @override
  State<SmsHistorySection> createState() => _SmsHistorySectionState();
}

class _SmsHistorySectionState extends State<SmsHistorySection>
    with WidgetsBindingObserver {
  static const _scope = '导入手机中 Android 可读取的所有已收和已发短信，不限日期。';
  SmsHistoryStatus? _status;
  Timer? _poll;
  bool _acting = false;
  bool _mayBeRunning = false;
  bool _permissionDenied = false;
  bool _statusError = false;
  String? _actionError;
  Future<void>? _reading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          !_acting &&
          TickerMode.valuesOf(context).enabled) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    if (_mayBeRunning || _status?.busy == true) {
      // Android 也会在退到后台时暂停；退出页面但仍在前台则由此通知。
      unawaited(SmsSync.pauseHistory().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh(fresh: true));
  }

  Future<void> _refresh({bool fresh = false}) async {
    if (_reading case final reading?) {
      await reading;
      if (!fresh || !mounted) return;
    }
    await (_reading ??= _readStatus().whenComplete(() => _reading = null));
  }

  Future<void> _readStatus() async {
    try {
      final status = await SmsSync.historyStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _statusError = false;
          if (status.permission) _permissionDenied = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statusError = true);
    }
  }

  Future<void> _act(
    Future<void> Function() action, {
    required String error,
  }) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _actionError = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) await _refresh(fresh: true);
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _confirm(
    SmsHistoryStatus status, {
    required bool continuing,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(continuing ? '继续导入历史短信？' : '导入历史短信？'),
        content: Text(
          [
            _scope,
            '短信原文、收发对象和时间会发送到当前连接的 Pi Muse 服务器，可能包含验证码、账单等敏感信息。导入不会触发模型分析。',
            if (widget.connectionUsesHttp) '当前使用 HTTP，短信和连接令牌在传输时未加密。',
            if (!status.permission) '请先授予读取短信权限。授权后不会自动上传。',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              !status.permission
                  ? '去授权'
                  : continuing
                  ? '继续上传'
                  : '开始上传',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!status.permission) {
      await _act(() async {
        final granted = await SmsSync.requestHistoryPermission();
        if (mounted) setState(() => _permissionDenied = !granted);
      }, error: '无法请求读取短信权限，请重试。');
      return;
    }
    await _act(() async {
      _mayBeRunning = true;
      await SmsSync.startHistory();
    }, error: '无法开始历史导入，请重试。');
  }

  String _summary(SmsHistoryStatus status) => switch (status.state) {
    'running' => '正在读取并分批上传，请暂时留在此页。',
    'paused' => '导入已暂停。下次可从上次进度继续。',
    'complete' => status.failed == 0 ? '本次导入完成。' : '本次扫描结束，有短信未能导入。',
    'permission' => '导入已暂停，需要 Android 读取短信权限。',
    'auth' || 'connection' => '服务器连接不可用，请重新连接后继续。',
    'network' => '无法连接服务器，恢复网络后可继续。',
    'checking' when status.busy => '正在核对上一批是否已被服务器接收。',
    'checking' when status.retryReady => '已核对上一批。点「继续导入」补传服务器上没有的短信。',
    'checking' => '上一批结果待确认。继续时先核对，不会直接重发。',
    'conflict' => '服务器上的记录与要导入的短信冲突。已中止此批，未计为成功。',
    'error' => '历史导入遇到错误，已保留确认进度。',
    _ => '导入独立于新短信同步，不会读取 MMS 或 RCS 消息。',
  };

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final continuing =
        status != null && status.state != 'idle' && status.state != 'complete';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('历史短信导入', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(_scope),
          const SizedBox(height: 8),
          if (status != null) ...[
            Text(_summary(status)),
            if (status.state != 'idle')
              Text(
                '已导入 ${status.accepted} 条 · 已跳过 ${status.skipped} 条 · 未能导入 ${status.failed} 条',
              ),
          ],
          if (status?.permission == false) ...[
            const SizedBox(height: 4),
            Text(
              _permissionDenied || continuing
                  ? widget.permissionHelp
                  : '首次导入需要单独授予读取短信权限。',
            ),
          ],
          if (_statusError || _actionError != null) ...[
            const SizedBox(height: 4),
            Text(
              _actionError ?? '无法读取历史导入状态，请重试。',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          if (_statusError && status?.busy != true)
            OutlinedButton(
              onPressed: _acting ? null : () => _refresh(fresh: true),
              child: const Text('刷新导入状态'),
            )
          else if (status?.busy == true) ...[
            const LinearProgressIndicator(),
            OutlinedButton.icon(
              onPressed: _acting
                  ? null
                  : () => _act(SmsSync.pauseHistory, error: '无法暂停历史导入，请重试。'),
              icon: const Icon(Icons.pause),
              label: const Text('暂停导入'),
            ),
          ] else
            FilledButton.tonalIcon(
              onPressed: status == null || _acting
                  ? null
                  : () => _confirm(status, continuing: continuing),
              icon: const Icon(Icons.upload_outlined),
              label: Text(continuing ? '继续导入' : '导入历史短信'),
            ),
          if (status?.permission == false && (_permissionDenied || continuing))
            OutlinedButton.icon(
              onPressed: _acting
                  ? null
                  : () => _act(
                      SmsSync.openAppSettings,
                      error: '无法打开 Android 应用设置，请从系统设置进入。',
                    ),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('打开短信权限设置'),
            ),
        ],
      ),
    );
  }
}
