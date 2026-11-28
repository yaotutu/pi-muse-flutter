import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/app-update/app_update.dart';
import '../features/app-update/app_update_sheet.dart';
import '../features/appearance/appearance.dart';
import '../features/chat/chat_controller.dart';
import '../features/connection/connection_page.dart';
import '../features/connection/server_connection.dart';
import '../features/sms-sync/sms_sync.dart';
import '../network/api.dart';
import 'workspace_page.dart';

class PiMuseApp extends StatefulWidget {
  const PiMuseApp({super.key});

  @override
  State<PiMuseApp> createState() => _PiMuseAppState();
}

class _PiMuseAppState extends State<PiMuseApp> with WidgetsBindingObserver {
  static const _connections = ServerConnectionStore();
  static const _paletteKey = 'pi-muse-palette';
  static const _themeModeKey = 'pi-muse-theme-mode';
  final _preferences = SharedPreferencesAsync();
  late final _appearance = AppearanceSettings(
    readPalette: () => _preferences.getString(_paletteKey),
    writePalette: (id) => _preferences.setString(_paletteKey, id),
    readThemeMode: () => _preferences.getString(_themeModeKey),
    writeThemeMode: (id) => _preferences.setString(_themeModeKey, id),
  );
  ChatController? _chat;
  Uri? _address;
  String? _storageError;
  bool _loading = true;
  final _updates = AppUpdateController();
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  (String, AppUpdateStatus)? _updateNotice;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updates.addListener(_notifyAppUpdate);
    _restore();
  }

  void _notifyAppUpdate() {
    final status = _updates.status;
    final version = _updates.release?.version;
    if (version == null ||
        (status != AppUpdateStatus.downloading &&
            status != AppUpdateStatus.permission) ||
        _updateNotice == (version, status)) {
      return;
    }
    _updateNotice = (version, status);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _updates.status != status) return;
      final messenger = _messenger.currentState;
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            status == AppUpdateStatus.permission
                ? '已下载 $version，安装前需要授权'
                : '发现 Pi Muse 新版本 $version',
          ),
          action: SnackBarAction(
            label: '查看更新',
            onPressed: () => _navigator.currentState?.push<void>(
              MaterialPageRoute(
                builder: (_) => AppUpdateSheet(controller: _updates),
              ),
            ),
          ),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _restore() async {
    await Future.wait([_restoreConnection(), _appearance.restore()]);
    unawaited(SmsSync.resume());
    if (!mounted) return;
    setState(() => _loading = false);
    _updates.setForeground(
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
  }

  Future<void> _restoreConnection() async {
    try {
      final saved = await _connections.restore();
      if (saved != null && mounted) _useConnection(saved);
    } catch (_) {
      _storageError = '本机连接记录无法读取，请重新连接';
    }
  }

  void _useConnection(ServerConnection connection) {
    final (:address, :token) = connection;
    _chat?.dispose();
    _address = address;
    _updates.setServerOrigin(address);
    _chat = ChatController(
      MuseApi(address, token: token),
      () => MuseApi(address, token: token),
    )..start();
  }

  Future<void> _connect(Uri address, String key) async {
    final connection = await _connections.connect(address, key);
    await SmsSync.resume(connectionChanged: true);
    if (mounted) setState(() => _useConnection(connection));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_loading || state != AppLifecycleState.resumed) {
      _updates.setForeground(state == AppLifecycleState.resumed);
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final backgroundDuration = _backgroundedAt == null
          ? null
          : DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
      _chat?.onAppResumed(backgroundDuration);
      if (!_loading) unawaited(SmsSync.resume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appearance.dispose();
    _chat?.dispose();
    _updates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _appearance,
    builder: (_, _) => _buildApp(),
  );

  Future<bool> _confirmReconnect(
    BuildContext dialogContext,
    ChatController chat,
  ) async {
    final hasRun = chat.conversations.values.any(
      (conversation) => conversation.submission?.running == true,
    );
    final hasDraft = chat.conversations.values.any(
      (conversation) =>
          conversation.draft.isNotEmpty ||
          conversation.draftAttachments.isNotEmpty ||
          conversation.submission != null,
    );
    if (!hasRun && !hasDraft) return true;
    final proceed = await showDialog<bool>(
      context: dialogContext,
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
    return proceed == true;
  }

  Widget _buildApp() {
    final chat = _chat;
    final palette = _appearance.palette;
    return MaterialApp(
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      debugShowCheckedModeBanner: false,
      title: 'Pi Muse',
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: museTheme(palette.colors(Brightness.light)),
      darkTheme: museTheme(palette.colors(Brightness.dark)),
      themeMode: _appearance.themeMode,
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
          Widget buildSettingsConnection() => ConnectionPage(
            settingsMode: true,
            address: _address,
            onBeforeConnect: (dialogContext) =>
                _confirmReconnect(dialogContext, chat),
            onConnect: _connect,
          );
          return WorkspacePage(
            key: ObjectKey(chat),
            chat: chat,
            appearance: _appearance,
            connectionUsesHttp: _address?.scheme == 'http',
            updates: _updates,
            connectionBuilder: (_) => buildSettingsConnection(),
          );
        },
      ),
    );
  }
}
