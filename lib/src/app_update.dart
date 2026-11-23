import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_update_bridge.dart';
import 'app_update_releases.dart';

enum AppUpdateStatus {
  loading,
  unsupported,
  idle,
  checking,
  unpublished,
  current,
  downloading,
  ready,
  permission,
  installing,
  cancelled,
  checkFailed,
  downloadFailed,
  installFailed,
}

/// 一个任务负责从检查到下载的整个过程。取消后等到网络与原生任务收尾才允许重试。
class AppUpdateController extends ChangeNotifier {
  AppUpdateController({this.lookupRelease = getLatestRelease}) {
    unawaited(_initialize());
  }

  static const autoCheckInterval = Duration(hours: 1);
  final Future<AppRelease?> Function(HttpClient) lookupRelease;

  AppUpdateStatus _status = AppUpdateStatus.loading;
  String? _currentVersion;
  AppRelease? _release;
  int _bytesWritten = 0;
  String? _message;
  bool _busy = false;
  bool _disposed = false;
  bool _foreground = false;
  bool _cancelled = false;
  bool _autoInstallPending = false;
  String? _blockedVersion;
  DateTime? _lastCheck;
  Timer? _timer;
  HttpClient? _lookupClient;

  AppUpdateStatus get status => _status;
  String? get currentVersion => _currentVersion;
  AppRelease? get release => _release;
  int get bytesWritten => _bytesWritten;
  String? get message => _message;
  bool get busy => _busy;

  Future<void> _initialize() async {
    try {
      final device = await AppUpdateBridge.device();
      if (_disposed) return;
      _currentVersion = device?.version;
      if (device?.supported == true) {
        _publish(AppUpdateStatus.idle);
        _startChecking();
      } else {
        _publish(
          AppUpdateStatus.unsupported,
          device == null ? '请在 Android 正式版中检查更新。' : '调试版请通过开发工具更新。',
        );
      }
    } catch (_) {
      if (!_disposed) _publish(AppUpdateStatus.unsupported, '无法读取当前安装版本。');
    }
  }

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    if (foreground) {
      _maybeInstall();
      _startChecking();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startChecking() {
    if (!_foreground ||
        _status == AppUpdateStatus.loading ||
        _status == AppUpdateStatus.unsupported) {
      return;
    }
    unawaited(check());
    _timer ??= Timer.periodic(autoCheckInterval, (_) => unawaited(check()));
  }

  Future<void> check({bool manual = false}) async {
    if (_disposed ||
        _busy ||
        !_foreground ||
        _currentVersion == null ||
        _status == AppUpdateStatus.unsupported) {
      return;
    }
    final cached = switch (_status) {
      AppUpdateStatus.ready ||
      AppUpdateStatus.permission ||
      AppUpdateStatus.installFailed => _release,
      _ => null,
    };
    final previousStatus = _status;
    final now = DateTime.now();
    final last = _lastCheck;
    if (!manual && last != null && now.difference(last) < autoCheckInterval) {
      return;
    }
    _lastCheck = now;
    if (manual) _blockedVersion = null;

    await _run(
      () async {
        if (cached == null) {
          _release = null;
          _bytesWritten = 0;
          _publish(AppUpdateStatus.checking);
        } else {
          notifyListeners();
        }
        if (_disposed || _cancelled) return;
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 8);
        _lookupClient = client;
        final AppRelease? found;
        try {
          found = await lookupRelease(client);
        } finally {
          client.close(force: true);
          _lookupClient = null;
        }
        if (_disposed || _cancelled) return;
        if (cached != null &&
            (found == null || !isNewerVersion(found.version, cached.version))) {
          return;
        }
        if (found == null) {
          _publish(AppUpdateStatus.unpublished);
        } else if (!isNewerVersion(found.version, _currentVersion!)) {
          _publish(AppUpdateStatus.current);
        } else if (!manual && _blockedVersion == found.version) {
          _release = found;
          _publish(AppUpdateStatus.cancelled);
        } else {
          await _download(found);
        }
      },
      cached == null ? AppUpdateStatus.checkFailed : previousStatus,
      '检查更新失败，请稍后重试。',
    );
  }

  Future<void> retryDownload() async {
    final release = _release;
    if (_disposed || _busy || !_foreground || release == null) return;
    _blockedVersion = null;
    await _run(
      () => _download(release),
      AppUpdateStatus.downloadFailed,
      '下载或校验安装包失败，请重试。',
    );
  }

  Future<void> _download(AppRelease release) async {
    _autoInstallPending = false;
    _release = release;
    _bytesWritten = 0;
    _publish(AppUpdateStatus.downloading);
    if (_disposed || _cancelled) return;
    try {
      final verified = await AppUpdateBridge.download(release, (bytes) {
        if (_disposed || _cancelled) return;
        _bytesWritten = bytes.clamp(0, release.size);
        notifyListeners();
      });
      if (_disposed || _cancelled) return;
      if (!verified) throw StateError('Download did not complete');
      _bytesWritten = release.size;
      _autoInstallPending = true;
      _publish(AppUpdateStatus.ready, '安装包已校验，应用将在前台打开系统安装界面。');
    } catch (_) {
      if (!_disposed && !_cancelled) {
        _publish(AppUpdateStatus.downloadFailed, '下载或校验安装包失败，请重试。');
      }
    }
  }

  void cancel() {
    final status = _status;
    if (status != AppUpdateStatus.checking &&
        status != AppUpdateStatus.downloading) {
      return;
    }
    _cancelled = true;
    _lookupClient?.close(force: true);
    if (status == AppUpdateStatus.downloading) {
      _blockedVersion = _release?.version;
      unawaited(_cancelNativeDownload());
    }
    _publish(AppUpdateStatus.cancelled);
  }

  Future<void> _cancelNativeDownload() async {
    try {
      await AppUpdateBridge.cancel();
    } catch (_) {
      // 即使通道已关闭，已取消任务的回调也不能更新页面或启动安装器。
    }
  }

  void _maybeInstall() {
    if (!_disposed && _autoInstallPending && _foreground && !_busy) {
      unawaited(install());
    }
  }

  Future<void> install() async {
    if (_disposed ||
        _busy ||
        !_foreground ||
        (_status != AppUpdateStatus.ready &&
            _status != AppUpdateStatus.permission &&
            _status != AppUpdateStatus.installFailed)) {
      return;
    }
    _autoInstallPending = false;
    await _run(
      () async {
        _publish(AppUpdateStatus.installing);
        final opened = await AppUpdateBridge.install();
        if (_disposed) return;
        if (opened) {
          _publish(AppUpdateStatus.ready, '请在 Android 界面确认安装。');
        } else {
          _publish(AppUpdateStatus.permission, '请先允许 Pi Muse 安装未知应用。');
        }
      },
      AppUpdateStatus.installFailed,
      '无法打开安装器，可重试安装或重新下载安装包。',
    );
  }

  Future<void> openInstallSettings() async {
    if (_disposed ||
        _busy ||
        !_foreground ||
        _status != AppUpdateStatus.permission) {
      return;
    }
    await _run(
      () async {
        await AppUpdateBridge.openInstallSettings();
        if (!_disposed) {
          _publish(AppUpdateStatus.permission, '授权后返回应用，点「继续安装」。');
        }
      },
      AppUpdateStatus.permission,
      '无法打开系统设置，请在系统中授权后继续安装。',
    );
  }

  Future<void> _run(
    Future<void> Function() action,
    AppUpdateStatus failure,
    String fallback,
  ) async {
    _busy = true;
    _cancelled = false;
    try {
      await action();
    } catch (error) {
      if (!_disposed && !_cancelled) {
        _publish(
          failure,
          error is ReleaseCheckException ? error.message : fallback,
        );
      }
    } finally {
      _busy = false;
      if (!_disposed) {
        notifyListeners();
        _maybeInstall();
      }
    }
  }

  void _publish(AppUpdateStatus status, [String? message]) {
    _status = status;
    _message = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _lookupClient?.close(force: true);
    if (_status == AppUpdateStatus.downloading) {
      unawaited(_cancelNativeDownload());
    }
    super.dispose();
  }
}
