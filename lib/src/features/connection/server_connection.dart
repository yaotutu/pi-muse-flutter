import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../network/api.dart';
import '../../network/server_origin.dart';

typedef ServerConnection = ({Uri address, String token});

class ServerConnectionStore {
  const ServerConnectionStore();

  static const _storage = FlutterSecureStorage();
  // Android 后台短信同步也读取这条连接记录。
  static const _connectionKey = 'pi-muse-connection';

  Future<ServerConnection?> restore() async {
    final saved = await _storage.read(key: _connectionKey);
    if (saved == null) return null;
    final data = jsonDecode(saved) as Json;
    return (
      address: parseServerAddress(data['address'] as String),
      token: data['token'] as String,
    );
  }

  Future<ServerConnection> connect(Uri address, String accessKey) async {
    final api = MuseApi(address);
    try {
      final data = await api.post('/api/session', {
        if (accessKey.isNotEmpty) 'accessKey': accessKey,
      });
      final token = data['token'] as String;
      if (token.isEmpty) throw const FormatException();
      await _storage.write(
        key: _connectionKey,
        value: jsonEncode({'address': address.toString(), 'token': token}),
      );
      return (address: address, token: token);
    } finally {
      api.close();
    }
  }
}
