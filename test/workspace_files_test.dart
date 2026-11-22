import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/main.dart';
import 'package:pi_muse_flutter/src/api.dart';
import 'package:pi_muse_flutter/src/chat.dart';
import 'package:pi_muse_flutter/src/chat_page.dart';

const _directory = 'notes';
const _filename = '测试 #1.html';
const _filePath = '$_directory/$_filename';
const _source = '<h1>文件原文</h1>\n\n末行';

class _FileApi extends MuseApi {
  _FileApi() : super(Uri.parse('http://127.0.0.1'));

  final requests = <(String, String)>[];
  bool missing = true;

  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    final target = query!['path']!;
    requests.add((path, target));
    if (path == workspaceFileContentPath) {
      if (missing) throw const ApiException(404, code: 'NOT_FOUND');
      return {
        'path': _filePath,
        'name': _filename,
        'kind': 'text',
        'size': 31,
        'mimeType': 'text/html',
        'content': _source,
      };
    }
    return {
      'path': target,
      'entries': target == '.'
          ? [
              {
                'name': _directory,
                'path': _directory,
                'kind': 'directory',
                'size': 0,
              },
            ]
          : [
              {
                'name': _filename,
                'path': _filePath,
                'kind': 'file',
                'size': 31,
              },
            ],
    };
  }
}

void main() {
  testWidgets('workspace menu opens nested files and retries with raw source', (
    tester,
  ) async {
    final api = _FileApi();
    final chat = ChatController(api, () => api);
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: museTheme(Brightness.light),
        home: ChatPage(chat: chat, onConnection: () {}),
      ),
    );
    await tester.tap(find.byTooltip('切换会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工作区文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_directory));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_filename));
    await tester.pumpAndSettle();
    expect(find.text('这个文件已不存在'), findsOneWidget);

    api.missing = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text(_source), findsOneWidget);
    expect(find.text('文件原文'), findsNothing);
    expect(api.requests, [
      ('/api/workspace/files', '.'),
      ('/api/workspace/files', _directory),
      (workspaceFileContentPath, _filePath),
      (workspaceFileContentPath, _filePath),
    ]);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(_filename), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('工作区文件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
