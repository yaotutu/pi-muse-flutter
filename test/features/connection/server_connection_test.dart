import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_muse_flutter/src/features/connection/server_connection.dart';
import 'package:pi_muse_flutter/src/network/api.dart';

void main() {
  const connections = ServerConnectionStore();
  const storage = FlutterSecureStorage();
  const key = 'pi-muse-connection';

  test('restores the existing connection record used by Android SMS', () async {
    FlutterSecureStorage.setMockInitialValues({
      key: '{"address":"https://example.test:8443/","token":"saved-token"}',
    });
    expect(await connections.restore(), (
      address: Uri.parse('https://example.test:8443'),
      token: 'saved-token',
    ));
  });

  test(
    'login sends the access key once and persists only the session token',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final origin = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
      final requests = <List<Object?>>[];
      server.listen((request) async {
        final json =
            jsonDecode(await utf8.decoder.bind(request).join()) as Json;
        requests.add([
          request.method,
          request.uri.path,
          json,
          request.headers.value(HttpHeaders.authorizationHeader),
        ]);
        request.response.headers.contentType = ContentType.json;
        if (json['accessKey'] == 'accepted-key') {
          request.response.write('{"token":"session-token"}');
        } else {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.write('{"error":"unauthorized"}');
        }
        await request.response.close();
      });

      final connection = await connections.connect(origin, 'accepted-key');
      expect(connection, (address: origin, token: 'session-token'));
      final saved = {
        key: jsonEncode({
          'address': origin.toString(),
          'token': 'session-token',
        }),
      };
      expect(await storage.readAll(), saved);

      await expectLater(
        connections.connect(origin, 'wrong-key'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      expect(await storage.readAll(), saved);
      expect(requests, [
        [
          'POST',
          '/api/session',
          {'accessKey': 'accepted-key'},
          null,
        ],
        [
          'POST',
          '/api/session',
          {'accessKey': 'wrong-key'},
          null,
        ],
      ]);
    },
  );
}
