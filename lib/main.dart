import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';

import 'src/api.dart';
import 'src/chat.dart';
import 'src/chat_page.dart';

void main() => runApp(const PiMuseApp());

ThemeData museTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xff15181e) : const Color(0xffffffff);
  final ink = dark ? const Color(0xffe7ebf2) : const Color(0xff232932);
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff244e79),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xffaccdf5) : const Color(0xff244e79),
        onPrimary: dark ? const Color(0xff102b47) : const Color(0xffffffff),
        primaryContainer: dark
            ? const Color(0xff253346)
            : const Color(0xffedf2f7),
        onPrimaryContainer: ink,
        surface: background,
        onSurface: ink,
        onSurfaceVariant: dark
            ? const Color(0xffacb6c5)
            : const Color(0xff556171),
        surfaceContainerLow: dark
            ? const Color(0xff1b2029)
            : const Color(0xfff8f9fb),
        surfaceContainer: dark
            ? const Color(0xff212630)
            : const Color(0xfff2f4f7),
        surfaceContainerHigh: dark
            ? const Color(0xff272e38)
            : const Color(0xffe9edf2),
        outlineVariant: dark
            ? const Color(0xff424d5c)
            : const Color(0xffd6dce5),
      );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  return ThemeData(
    colorScheme: colors,
    scaffoldBackgroundColor: background,
    dividerColor: colors.outlineVariant,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(height: 1.5),
      bodyMedium: TextStyle(height: 1.5),
    ),
  );
}

class PiMuseApp extends StatefulWidget {
  const PiMuseApp({super.key});

  @override
  State<PiMuseApp> createState() => _PiMuseAppState();
}

class _PiMuseAppState extends State<PiMuseApp> with WidgetsBindingObserver {
  static const _storage = FlutterSecureStorage();
  static const _connectionKey = 'pi-muse-connection';
  ChatController? _chat;
  Uri? _address;
  String? _storageError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreConnection();
  }

  Future<void> _restoreConnection() async {
    try {
      final saved = await _storage.read(key: _connectionKey);
      if (saved != null && mounted) {
        final data = jsonDecode(saved) as Json;
        _useConnection(
          parseServerAddress(data['address'] as String),
          data['token'] as String,
        );
      }
    } catch (_) {
      _storageError = '本机连接记录无法读取，请重新连接';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _useConnection(Uri address, String token) {
    _chat?.dispose();
    _address = address;
    _chat = ChatController(
      MuseApi(address, token: token),
      () => MuseApi(address, token: token),
    )..start();
  }

  Future<void> _connect(Uri address, String key) async {
    final auth = MuseApi(address);
    try {
      final data = await auth.post('/api/session', {
        if (key.isNotEmpty) 'accessKey': key,
      });
      final token = data['token'] as String;
      if (token.isEmpty) throw const FormatException();
      await _storage.write(
        key: _connectionKey,
        value: jsonEncode({'address': address.toString(), 'token': token}),
      );
      if (mounted) setState(() => _useConnection(address, token));
    } finally {
      auth.close();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _chat?.reconnect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chat?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pi Muse',
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: museTheme(Brightness.light),
      darkTheme: museTheme(Brightness.dark),
      home: Builder(
        builder: (context) {
          if (_loading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (chat == null) {
            return ConnectionPage(onConnect: _connect, notice: _storageError);
          }
          return ChatPage(
            key: ObjectKey(chat),
            chat: chat,
            onConnection: () async {
              final hasRun = chat.conversations.values.any(
                (conversation) => conversation.submission?.running == true,
              );
              final hasDraft = chat.conversations.values.any(
                (conversation) =>
                    conversation.draft.isNotEmpty ||
                    conversation.submission != null,
              );
              if (hasRun || hasDraft) {
                final proceed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('更换服务器连接？'),
                    content: Text(
                      hasRun
                          ? '保存新连接会停止本机正在进行的回复，并清空本机的会话草稿。'
                          : '保存新连接会清空本机的会话草稿，不会删除服务器上的记录。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('返回'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('继续'),
                      ),
                    ],
                  ),
                );
                if (proceed != true || !context.mounted) return;
              }
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) =>
                      ConnectionPage(address: _address, onConnect: _connect),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    super.key,
    required this.onConnect,
    this.address,
    this.notice,
  });

  final Future<void> Function(Uri address, String key) onConnect;
  final Uri? address;
  final String? notice;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: canPop ? AppBar(title: const Text('服务器连接')) : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/avatar/idle.png',
                      height: 116,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(height: 8),
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
                    if (_address.text.trimLeft().startsWith('http://'))
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('HTTP 连接未加密，请在可信网络中使用。'),
                      ),
                    if ((_error ?? widget.notice) case final String message)
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
                      child: Text(_busy ? '正在连接…' : '连接'),
                    ),
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
