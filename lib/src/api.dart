import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  const ApiException(this.status, {this.code});

  final int status;
  final String? code;

  String get message => switch (status) {
    0 => 'Connection failed.',
    408 => 'Request timed out.',
    502 => 'Invalid server response.',
    _ => 'Request failed.',
  };

  @override
  String toString() => 'ApiException ($status): $message';
}

class SseFrame {
  const SseFrame({this.event, required this.data});

  final String? event;
  final Json data;
}

const _maxSseFrameBytes = 12 * 1024 * 1024;

Stream<SseFrame> decodeSse(Stream<List<int>> bytes) async* {
  yield* bytes
      .expand(_SseDecoder().add)
      .transform(
        StreamTransformer<SseFrame, SseFrame>.fromHandlers(
          handleError: (error, stack, sink) {
            sink.addError(error, stack);
            sink.close();
          },
        ),
      );
}

class _SseDecoder {
  final _frame = BytesBuilder();
  bool _lineHasContent = false;
  bool _skipLf = false;
  bool _atStart = true;

  Iterable<SseFrame> add(List<int> chunk) sync* {
    var start = 0;
    for (var index = 0; index < chunk.length; index++) {
      final byte = chunk[index];
      if (_skipLf) {
        _skipLf = false;
        if (byte == 10) continue;
      }
      if (byte != 10 && byte != 13) {
        _lineHasContent = true;
        continue;
      }
      _skipLf = byte == 13;
      if (_lineHasContent) {
        _lineHasContent = false;
        continue;
      }

      // CR/LF 不会出现在 UTF-8 多字节字符内部。仅在完整帧到达后解码，EOF 丢弃残帧。
      _append(chunk, start, index);
      start = index + 1;
      final frame = _decodeFrame(_frame.takeBytes());
      if (frame != null) yield frame;
    }
    _append(chunk, start, chunk.length);
  }

  void _append(List<int> chunk, int start, int end) {
    if (_frame.length + end - start > _maxSseFrameBytes) {
      throw const ApiException(502);
    }
    if (end == start) return;
    _frame.add(
      start == 0 && end == chunk.length ? chunk : chunk.sublist(start, end),
    );
  }

  SseFrame? _decodeFrame(Uint8List bytes) {
    var text = _decodeUtf8(bytes);
    // Dart 解码时会去掉起始 BOM，SSE 只允许在整个流开头去掉一次。
    if (!_atStart &&
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf) {
      text = '﻿$text';
    }
    _atStart = false;

    String? event;
    final data = <String>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty || line.startsWith(':')) continue;
      final separator = line.indexOf(':');
      final field = separator < 0 ? line : line.substring(0, separator);
      var value = separator < 0 ? '' : line.substring(separator + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      if (field == 'event') event = value.isEmpty ? null : value;
      if (field == 'data') data.add(value);
    }
    if (data.isEmpty) return null;
    return SseFrame(event: event, data: _decodeJson(data.join('\n')));
  }
}

String _decodeUtf8(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const ApiException(502);
  }
}

Json _decodeJson(String text) {
  try {
    final value = jsonDecode(text);
    if (value is Json) return value;
  } on FormatException {
    // JSON 解码异常可能包含正文，传输层只返回通用错误。
  }
  throw const ApiException(502);
}

final _serverOrigin = RegExp(
  r'^https?://[^/?#\\\s@\x00-\x1f\x7f]+/?$',
  caseSensitive: false,
);

Uri parseServerAddress(String input) {
  const invalid = FormatException('Enter an HTTP or HTTPS server origin.');
  final address = input.trim();
  if (!_serverOrigin.hasMatch(address)) throw invalid;
  final uri = Uri.tryParse(address);
  if (uri == null || uri.host.isEmpty || uri.port < 1 || uri.port > 65535) {
    throw invalid;
  }
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.port);
}

const _connectTimeout = Duration(seconds: 8);
const _handshakeTimeout = Duration(seconds: 15);
const _restTimeout = Duration(seconds: 30);
const _errorReadTimeout = Duration(seconds: 3);
// 工作区每 30 秒发送注释心跳，允许一次延迟。计时在 SSE 解码前，心跳也会重置计时。
const _workspaceIdleTimeout = Duration(seconds: 75);
const _maxRestBytes = 32 * 1024 * 1024;
const _maxErrorBytes = 64 * 1024;
const workspaceFileContentPath = '/api/workspace/files/content';
const maxWorkspaceFileBytes = 8 * 1024 * 1024;
// 文件原文中的控制字符在 JSON 中可能编码成 6 字节，另留文件元数据的空间。
const _maxWorkspaceFileResponseBytes = maxWorkspaceFileBytes * 6 + 64 * 1024;
final _errorCode = RegExp(r'^[A-Z][A-Z0-9_]{0,63}$');

class MuseApi {
  MuseApi(Uri base, {String? token})
    : _base = parseServerAddress(base.toString()),
      _token = token;

  final Uri _base;
  final String? _token;
  final _client = HttpClient()..connectionTimeout = _connectTimeout;

  Future<Json> get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);

  Future<Json> post(String path, Json body) =>
      _request('POST', path, body: body);

  Stream<SseFrame> events() => _stream('GET', '/api/events', workspace: true);

  Stream<SseFrame> run(Json body) =>
      _stream('POST', '/api/conversation/run', body: body);

  void close() => _client.close(force: true);

  Future<Json> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Json? body,
  }) async {
    final elapsed = Stopwatch()..start();
    try {
      final response = await _open(method, path, query: query, body: body);
      await _checkStatus(response, body);
      return await _readJson(
        response,
        _restTimeout - elapsed.elapsed,
        path == workspaceFileContentPath
            ? _maxWorkspaceFileResponseBytes
            : _maxRestBytes,
      );
    } catch (error) {
      throw _safeError(error);
    }
  }

  Stream<SseFrame> _stream(
    String method,
    String path, {
    Json? body,
    bool workspace = false,
  }) async* {
    try {
      final response = await _open(method, path, body: body, sse: true);
      await _checkStatus(response, body);
      if (response.headers.contentType?.mimeType != 'text/event-stream') {
        await response.listen(null).cancel();
        throw const ApiException(502);
      }
      final bytes = workspace
          ? response.timeout(_workspaceIdleTimeout)
          : response;
      yield* decodeSse(bytes).handleError((Object error) {
        throw _safeError(error);
      });
    } catch (error) {
      throw _safeError(error);
    }
  }

  Future<HttpClientResponse> _open(
    String method,
    String path, {
    Map<String, String>? query,
    Json? body,
    bool sse = false,
  }) async {
    final endpoint = Uri.tryParse(path);
    if (endpoint == null ||
        !path.startsWith('/') ||
        path.contains('\\') ||
        endpoint.hasAuthority ||
        endpoint.hasQuery ||
        endpoint.hasFragment) {
      throw const ApiException(400);
    }
    final uri = _base.replace(path: endpoint.path, queryParameters: query);
    final payload = body == null ? null : utf8.encode(jsonEncode(body));
    HttpClientRequest? request;
    var expired = false;

    Future<HttpClientResponse> send() async {
      final current = await _client.openUrl(method, uri);
      request = current;
      // openUrl 可能在握手期限后才返回，此时在发送请求头前取消。
      if (expired) {
        current.done.ignore();
        current.abort();
        throw const ApiException(408);
      }
      current.followRedirects = false;
      current.headers.set(
        HttpHeaders.acceptHeader,
        sse ? 'text/event-stream' : 'application/json',
      );
      final token = _token;
      if (token != null && token.isNotEmpty) {
        current.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (payload != null) {
        current.headers.contentType = ContentType.json;
        current.contentLength = payload.length;
        current.add(payload);
      }
      return current.close();
    }

    try {
      return await send().timeout(
        _handshakeTimeout,
        onTimeout: () {
          expired = true;
          throw const ApiException(408);
        },
      );
    } catch (_) {
      request?.done.ignore();
      request?.abort();
      rethrow;
    }
  }

  Future<void> _checkStatus(HttpClientResponse response, Json? body) async {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    if (status >= 300 && status < 400) {
      await response.listen(null).cancel();
      throw ApiException(status);
    }

    String? code;
    try {
      final error = await _readJson(
        response,
        _errorReadTimeout,
        _maxErrorBytes,
      );
      final value = error['code'];
      final accessKey = body?['accessKey'];
      if (value is String &&
          _errorCode.hasMatch(value) &&
          !_containsSecret(value, _token) &&
          !_containsSecret(value, accessKey)) {
        code = value;
      }
    } catch (_) {
      // 错误正文缺失、过大或不可解码时仍保留原始 HTTP 状态。
    }
    throw ApiException(status, code: code);
  }
}

bool _containsSecret(String value, Object? secret) =>
    secret is String && secret.isNotEmpty && value.contains(secret);

ApiException _safeError(Object error) => switch (error) {
  ApiException exception => exception,
  TimeoutException() => const ApiException(408),
  FormatException() => const ApiException(502),
  _ => const ApiException(0),
};

Future<Json> _readJson(
  HttpClientResponse response,
  Duration timeout,
  int maxBytes,
) async {
  if (response.contentLength > maxBytes) {
    await response.listen(null).cancel();
    throw const ApiException(502);
  }
  final bytes = BytesBuilder();
  final chunks = StreamIterator<List<int>>(response);
  final elapsed = Stopwatch()..start();
  try {
    while (true) {
      final remaining = timeout - elapsed.elapsed;
      // 先开始读取，超过期限时 finally 会取消实际的响应订阅。
      final next = chunks.moveNext();
      if (remaining <= Duration.zero) {
        next.ignore();
        throw const ApiException(408);
      }
      if (!await next.timeout(remaining)) break;
      final chunk = chunks.current;
      if (bytes.length + chunk.length > maxBytes) {
        throw const ApiException(502);
      }
      bytes.add(chunk);
    }
    return _decodeJson(_decodeUtf8(bytes.takeBytes()));
  } finally {
    await chunks.cancel();
  }
}
