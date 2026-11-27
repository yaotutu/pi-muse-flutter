import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/api.dart';
import 'package:pi_muse_flutter/src/appearance.dart';
import 'package:pi_muse_flutter/src/chat.dart';
import 'package:pi_muse_flutter/src/chat_page.dart';

class _FakeMcpApi extends MuseApi {
  _FakeMcpApi() : super(Uri.parse('http://127.0.0.1'));

  final calls = <(String, String, Json?)>[];
  final servers = <String, Json>{
    'docs': {
      'name': 'docs',
      'transport': 'http',
      'enabled': true,
      'description': 'Official docs server',
      'timeout': 60,
      'status': 'connected',
      'error': null,
      'connectedAt': '2026-11-27T12:00:00.000Z',
      'toolCount': 1,
      'tools': [
        {
          'name': 'search_docs',
          'exposedName': 'mcp__docs__search_docs',
          'description': 'Search documentation',
        },
      ],
      'command': null,
      'args': <String>[],
      'cwd': null,
      'envKeys': <String>[],
      'url': 'https://example.com/mcp',
      'headerNames': ['Authorization'],
    },
  };
  final overrides = <String, bool>{};

  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    calls.add(('GET', path, null));
    if (path == '/api/mcp/servers') {
      final list = servers.values.toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      return {'servers': list, 'diagnostics': <Json>[]};
    }
    if (path == '/api/assistant/mcp') {
      final list = servers.values.toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      return {
        'servers': [
          for (final server in list)
            {
              'name': server['name'],
              'transport': server['transport'],
              'description': server['description'],
              'globalEnabled': server['enabled'],
              'status': server['status'],
              'toolCount': server['toolCount'],
              'defaultEnabled': true,
              'enabled': overrides[server['name']] ?? true,
              'effectiveEnabled':
                  (server['enabled'] as bool) &&
                  (overrides[server['name']] ?? true),
            },
        ],
        'overrides': Map<String, bool>.from(overrides),
      };
    }
    throw UnimplementedError('Unexpected GET $path');
  }

  @override
  Future<Json> put(String path, Json body) async {
    calls.add(('PUT', path, body));
    if (path == '/api/assistant/mcp') {
      final raw = body['overrides'] as Map<String, dynamic>;
      overrides
        ..clear()
        ..addAll(raw.map((k, v) => MapEntry(k, v as bool)));
      return await get('/api/assistant/mcp');
    }
    if (path.startsWith('/api/mcp/servers/')) {
      final name = Uri.decodeComponent(path.split('/').last);
      final isStdio = body.containsKey('command');
      final headers = (body['headers'] as Map<String, dynamic>? ?? const {});
      final env = (body['env'] as Map<String, dynamic>? ?? const {});
      final entry = <String, dynamic>{
        'name': name,
        'transport': isStdio ? 'stdio' : 'http',
        'enabled': body['enabled'] ?? true,
        'description': body['description'] ?? '',
        'timeout': body['timeout'] ?? 60,
        'status': (body['enabled'] ?? true) ? 'connected' : 'disabled',
        'error': null,
        'connectedAt': null,
        'toolCount': 0,
        'tools': <Json>[],
        'command': isStdio ? body['command'] : null,
        'args': isStdio ? (body['args'] ?? <String>[]) : <String>[],
        'cwd': isStdio ? body['cwd'] : null,
        'envKeys': env.keys.toList(),
        'url': isStdio ? null : body['url'],
        'headerNames': headers.keys.toList(),
      };
      servers[name] = entry;
      return {'server': entry};
    }
    throw UnimplementedError('Unexpected PUT $path');
  }

  @override
  Future<Json> patch(String path, Json body) async {
    calls.add(('PATCH', path, body));
    final name = Uri.decodeComponent(path.split('/').last);
    final current = Map<String, dynamic>.from(servers[name]!);
    if (body.containsKey('enabled')) {
      final enabled = body['enabled'] as bool;
      current['enabled'] = enabled;
      current['status'] = enabled ? 'connected' : 'disabled';
    }
    if (body.containsKey('description')) {
      current['description'] = body['description'];
    }
    if (body.containsKey('timeout')) {
      current['timeout'] = body['timeout'];
    }
    servers[name] = current;
    return {'server': current};
  }

  @override
  Future<Json> post(String path, [Json? body]) async {
    calls.add(('POST', path, body));
    final segments = path.split('/');
    final name = Uri.decodeComponent(segments[segments.length - 2]);
    return {'server': servers[name]};
  }

  @override
  Future<Json> delete(String path, [Json? body]) async {
    calls.add(('DELETE', path, body));
    final name = Uri.decodeComponent(path.split('/').last);
    servers.remove(name);
    overrides.remove(name);
    return {'ok': true, 'name': name};
  }
}

void main() {
  testWidgets(
    'settings opens MCP page, toggles switches, adds/edits/reconnects/deletes server',
    (tester) async {
      final api = _FakeMcpApi();
      final chat = ChatController(api, () => api);
      addTearDown(chat.dispose);
      final appearance = AppearanceSettings(
        readPalette: () async => null,
        writePalette: (_) async {},
      );
      addTearDown(appearance.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: museTheme(MusePalette.indigo.colors(Brightness.light)),
          home: ChatPage(
            chat: chat,
            appearance: appearance,
            onConnection: () {},
          ),
        ),
      );

      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MCP 服务'));
      await tester.pumpAndSettle();

      expect(find.text('docs'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('请求头键：Authorization'), findsOneWidget);

      // Expand tools
      await tester.tap(find.text('可用工具（1）'));
      await tester.pumpAndSettle();
      expect(find.text('search_docs'), findsOneWidget);

      // Only the single chat switch should appear on each card
      expect(find.text('聊天可用'), findsOneWidget);
      expect(find.text('全局启用'), findsNothing);
      expect(find.text('主聊天可用'), findsNothing);

      // Toggle chat switch off and back on
      await tester.tap(find.text('聊天可用'));
      await tester.pumpAndSettle();
      expect(api.overrides['docs'], isFalse);
      await tester.tap(find.text('聊天可用'));
      await tester.pumpAndSettle();
      expect(api.overrides['docs'], isTrue);

      // Edit description via PATCH (keeping headers intact)
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Official docs server'),
        'Updated docs description',
      );
      await tester.tap(find.text('保存配置'));
      await tester.pumpAndSettle();
      expect(api.servers['docs']!['description'], 'Updated docs description');
      expect(api.servers['docs']!['headerNames'], ['Authorization']);

      // Reconnect test
      await tester.tap(find.text('重连'));
      await tester.pumpAndSettle();
      expect(
        api.calls.any((call) => call.$1 == 'POST' && call.$2.endsWith('/reconnect')),
        isTrue,
      );

      // Add a new stdio MCP server
      await tester.tap(find.byTooltip('添加 MCP 服务'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '服务名称'),
        'local-fs',
      );
      await tester.tap(find.text('本地命令 (stdio)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '可执行命令'),
        'node',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '命令参数（可选，每行一个）'),
        'server.js',
      );
      await tester.scrollUntilVisible(
        find.text('保存配置'),
        200,
        scrollable: find.descendant(
          of: find.byType(Form),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.ensureVisible(find.text('保存配置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存配置'));
      await tester.pumpAndSettle();
      expect(api.servers.containsKey('local-fs'), isTrue);
      expect(api.servers['local-fs']!['transport'], 'stdio');

      // Delete the newly added server
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('删除').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(api.servers.containsKey('local-fs'), isFalse);

      expect(tester.takeException(), isNull);
    },
  );
}
