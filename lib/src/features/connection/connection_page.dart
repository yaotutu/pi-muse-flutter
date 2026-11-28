import 'package:material_ui/material_ui.dart';

import '../../network/api.dart';
import '../../network/server_origin.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    super.key,
    required this.onConnect,
    this.address,
    this.notice,
    this.settingsMode = false,
    this.onBeforeConnect,
  });

  final Future<void> Function(Uri address, String key) onConnect;
  final Uri? address;
  final String? notice;
  final bool settingsMode;
  final Future<bool> Function(BuildContext context)? onBeforeConnect;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late final _address = TextEditingController(text: widget.address?.toString());
  final _key = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    final closeAfter = navigator.canPop();
    final Uri address;
    try {
      address = parseServerAddress(_address.text);
    } on FormatException {
      setState(() => _error = '请输入完整的 HTTP 或 HTTPS 服务器地址，可带端口');
      return;
    }
    if (widget.onBeforeConnect case final before?) {
      final proceed = await before(context);
      if (!mounted || !proceed) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConnect(address, _key.text.trim());
      if (mounted) {
        _key.clear();
        if (closeAfter) navigator.pop();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException && error.status == 401
              ? '访问密钥不正确，请核对后重试'
              : '连接未保存，请检查服务器地址和网络',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _key.dispose();
    super.dispose();
  }

  List<Widget> _buildFormFields(ThemeData theme) {
    final httpNotice = _address.text.trimLeft().startsWith('http://');
    final notice = _error ?? widget.notice;
    return [
      TextField(
        controller: _address,
        enabled: !_busy,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: '服务器地址'),
        autocorrect: false,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _key,
        enabled: !_busy,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(labelText: '访问密钥'),
      ),
      if (httpNotice)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'HTTP 连接未加密，请在可信网络中使用。'
            '同步新短信或导入历史短信时，短信也会通过此连接发送。',
          ),
        ),
      if (notice case final String message)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            message,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? '正在连接…' : (widget.settingsMode ? '保存并连接' : '连接')),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canPop = Navigator.of(context).canPop();
    return PopScope(
      canPop: !_busy,
      child: widget.settingsMode
          ? Scaffold(
              appBar: AppBar(title: const Text('服务器连接')),
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('当前连接', style: theme.textTheme.titleLarge),
                              const SizedBox(height: 4),
                              Text(
                                '修改服务器地址或重新验证访问密钥。',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: colors.surfaceContainerLowest,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: colors.outlineVariant),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: _buildFormFields(theme),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : Scaffold(
              appBar: canPop ? AppBar(title: const Text('服务器连接')) : null,
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Pi Muse',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '连接你的助手服务器',
                            style: theme.textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          ..._buildFormFields(theme),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
