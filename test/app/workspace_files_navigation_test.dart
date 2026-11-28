import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/network/api.dart';
import 'package:pi_muse_flutter/src/features/appearance/appearance.dart';
import 'package:pi_muse_flutter/src/features/chat/chat_controller.dart';
import 'package:pi_muse_flutter/src/app/workspace_page.dart';

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
  testWidgets(
    'left navigation opens nested files and retries with raw source',
    (tester) async {
      final api = _FileApi();
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
          home: WorkspacePage(
            chat: chat,
            appearance: appearance,
            connectionBuilder: (_) => const SizedBox(),
          ),
        ),
      );
      final menuButton = find.byTooltip('打开导航菜单');
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      final drawer = find.byType(Drawer);
      final bounds = tester.getRect(drawer);
      expect(bounds.topLeft, Offset.zero);
      expect(
        bounds.height,
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      );
      expect(
        bounds.width,
        lessThan(tester.view.physicalSize.width / tester.view.devicePixelRatio),
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(drawer, findsNothing);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: drawer, matching: find.text('工作区文件')),
      );
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
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(menuButton, findsOneWidget);
      expect(drawer, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
