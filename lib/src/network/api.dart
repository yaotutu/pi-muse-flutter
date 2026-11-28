import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'api_response.dart';
import 'server_origin.dart';
import 'sse_decoder.dart';

export 'api_response.dart' show ApiException, Json;
export 'sse_decoder.dart' show SseFrame;

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

  Future<Json> post(String path, [Json? body]) =>
      _request('POST', path, body: body);

  Future<Json> put(String path, Json body) => _request('PUT', path, body: body);

  Future<Json> patch(String path, Json body) =>
      _request('PATCH', path, body: body);

  Future<Json> delete(String path, [Json? body]) =>
      _request('DELETE', path, body: body);

  Stream<SseFrame> events() => _stream('GET', '/api/events', workspace: true);

  Stream<SseFrame> run(Json body) =>
      _stream('POST', '/api/conversation/run', body: body);

  Stream<SseFrame> streamRun(String sessionId, String runId) => _stream(
    'GET',
    '/api/conversation/stream',
    query: {'sessionId': sessionId, 'runId': runId},
  );

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
    Map<String, String>? query,
    Json? body,
    bool workspace = false,
  }) async* {
    try {
      final response = await _open(
        method,
        path,
        query: query,
        body: body,
        sse: true,
      );
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
    return decodeApiJson(decodeApiUtf8(bytes.takeBytes()));
  } finally {
    await chunks.cancel();
  }
}
