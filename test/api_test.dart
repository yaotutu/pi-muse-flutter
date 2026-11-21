import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_muse_flutter/src/api.dart';

void main() {
  group('decodeSse', () {
    test('decodes CJK and CRLF when every byte is a separate chunk', () async {
      final wire = utf8.encode(
        '﻿event: ready\r\n'
        'data: {"label":"中文🐧"}\r\n\r\n'
        'data: {"type":"RUN_FINISHED"}\r\n\r\n',
      );
      final frames = await decodeSse(
        Stream.fromIterable(wire.map((byte) => [byte])),
      ).toList();

      expect(frames.map((frame) => frame.event), ['ready', null]);
      expect(frames.map((frame) => frame.data), [
        {'label': '中文🐧'},
        {'type': 'RUN_FINISHED'},
      ]);
    });

    test('joins data lines and skips comment heartbeats', () async {
      final frames = await decodeSse(
        Stream.value(
          utf8.encode(
            ': keep-alive\n\n'
            'event: update\r'
            'id: 123\r'
            'data:{"label":\r'
            ': comment inside a frame\r'
            'data: "a:b"}\r\r'
            'event: no_data\n\n'
            ': keep-alive\n\n',
          ),
        ),
      ).toList();

      expect(frames.single.event, 'update');
      expect(frames.single.data, {'label': 'a:b'});
    });

    test(
      'drops a partial frame at EOF even when its JSON is complete',
      () async {
        final frames = await decodeSse(
          Stream.value(
            utf8.encode('data: {"first":true}\n\ndata: {"partial":true}\n'),
          ),
        ).toList();

        expect(frames.single.data, {'first': true});
      },
    );

    test('drops a partial UTF-8 character in a truncated frame', () async {
      final bytes = [
        ...utf8.encode('data: {"label":"'),
        utf8.encode('中').first,
      ];
      expect(await decodeSse(Stream.value(bytes)).toList(), isEmpty);
    });

    test('reports invalid complete frames without exposing data', () async {
      await expectLater(
        decodeSse(Stream.value(utf8.encode('data: private-body\n\n'))),
        emitsInOrder([
          emitsError(
            isA<ApiException>()
                .having((error) => error.status, 'status', 502)
                .having(
                  (error) => error.toString(),
                  'text',
                  isNot(contains('private-body')),
                ),
          ),
          emitsDone,
        ]),
      );
    });
  });

  group('parseServerAddress', () {
    test('normalizes HTTP(S) origins and preserves non-default ports', () {
      expect(
        parseServerAddress(' HTTPS://Example.COM:443/ ').toString(),
        'https://example.com',
      );
      expect(
        parseServerAddress('http://127.0.0.1:12330/').toString(),
        'http://127.0.0.1:12330',
      );
      expect(
        parseServerAddress('http://[::1]:12330/').toString(),
        'http://[::1]:12330',
      );
    });

    test('rejects anything other than an HTTP(S) origin', () {
      for (final address in [
        '',
        'example.com:12330',
        'ftp://example.com',
        'http:///example.com',
        'http://example.com:65536',
        'https://user:pass@example.com',
        'https://@example.com',
        'https://example.com/prefix',
        'https://example.com/.',
        'https://example.com//',
        'https://example.com/?',
        'https://example.com/#',
        r'https://example.com\other',
      ]) {
        expect(() => parseServerAddress(address), throwsFormatException);
      }
    });
  });

  group('MuseApi', () {
    test(
      'sends Bearer authentication, UTF-8 JSON and encoded query values',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final api = MuseApi(
          Uri.http('127.0.0.1:${server.port}'),
          token: 'test-token',
        );
        addTearDown(api.close);
        server.listen((request) async {
          final response = request.response;
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode({
              'method': request.method,
              'path': request.uri.path,
              'word': request.uri.queryParameters['word'],
              'auth': request.headers.value(HttpHeaders.authorizationHeader),
              'body': await utf8.decoder.bind(request).join(),
            }),
          );
          await response.close();
        });

        final get = await api.get('/api/conversation', query: {'word': '中文&+'});
        expect(get['method'], 'GET');
        expect(get['path'], '/api/conversation');
        expect(get['word'], '中文&+');
        expect(get['auth'], 'Bearer test-token');

        final post = await api.post('/api/session', {'accessKey': '测试'});
        expect(post['method'], 'POST');
        expect(jsonDecode(post['body'] as String), {'accessKey': '测试'});
      },
    );

    test('keeps SSE handshake status and code and refuses redirects', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final api = MuseApi(
        Uri.http('127.0.0.1:${server.port}'),
        token: 'test-token',
      );
      addTearDown(api.close);
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        await request.drain<void>();
        final response = request.response;
        if (request.uri.path == '/api/events') {
          response.statusCode = HttpStatus.temporaryRedirect;
          response.headers.set(HttpHeaders.locationHeader, '/redirect-target');
        } else {
          response.statusCode = HttpStatus.conflict;
          response.headers.contentType = ContentType.json;
          response.write('{"code":"REVISION_CONFLICT","error":"private-body"}');
        }
        await response.close();
      });

      await expectLater(
        api.events().toList(),
        throwsA(
          isA<ApiException>().having((error) => error.status, 'status', 307),
        ),
      );
      await expectLater(
        api.run({'sessionId': 'main'}).toList(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.status, 'status', 409)
              .having((error) => error.code, 'code', 'REVISION_CONFLICT')
              .having(
                (error) => error.toString(),
                'text',
                isNot(contains('private-body')),
              ),
        ),
      );
      expect(paths, ['/api/events', '/api/conversation/run']);
    });
  });
}
