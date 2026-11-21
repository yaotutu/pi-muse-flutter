import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/main.dart';
import 'package:pi_muse_flutter/src/api.dart';
import 'package:pi_muse_flutter/src/chat.dart';
import 'package:pi_muse_flutter/src/chat_page.dart';
import 'package:pi_muse_flutter/src/visible_text.dart';

void main() {
  test('assistant projection hides incomplete and nested thinking blocks', () {
    expect(visibleAssistantText('Hello <thi'), 'Hello ');
    expect(visibleAssistantText('<think>private'), '');
    expect(
      visibleAssistantText('<THINK>hidden <think>nested</think></THINK>\n你好'),
      '你好',
    );
    expect(visibleAssistantText('`<think>` and 1 < 2'), '`<think>` and 1 < 2');
    const code = '```text\n<think>literal\n```\n<think>hidden';
    expect(visibleAssistantText(code), '```text\n<think>literal\n```\n');
  });

  testWidgets('the companion stays centered and above chat with the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final address = Uri.parse('http://localhost');
    final chat = ChatController(MuseApi(address), () => MuseApi(address));
    addTearDown(chat.dispose);
    chat.synchronized = true;
    chat.active.revision = 'empty';
    chat.active.dirty = false;
    final app = MaterialApp(
      theme: museTheme(Brightness.light),
      home: ChatPage(chat: chat, onConnection: () {}),
    );
    await tester.pumpWidget(app);
    expect(find.text('就绪'), findsOneWidget);
    final image = find.byType(Image);
    expect(tester.getCenter(image).dx, 180);
    final desktopHeight = tester.getSize(image).height;
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    await tester.pump();
    expect(tester.getCenter(image).dx, 180);
    expect(tester.getSize(image).height, lessThan(desktopHeight));
    expect(tester.getBottomRight(find.byType(TextField)).dy, lessThan(400));
    await tester.pumpWidget(const SizedBox());
  });
}
