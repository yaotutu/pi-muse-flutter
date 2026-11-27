import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pi_muse_flutter/src/api.dart';
import 'package:pi_muse_flutter/src/appearance.dart';
import 'package:pi_muse_flutter/src/chat.dart';
import 'package:pi_muse_flutter/src/chat_page.dart';

class _FakeSubagentsApi extends MuseApi {
  _FakeSubagentsApi() : super(Uri.parse('http://127.0.0.1'));

  bool smsEnabled = false;
  bool habitsEnabled = true;
  String smsInstructions = 'Important verification codes only';
  final smsMcp = <String>[];
  String? savedSmsInstructions;
  List<String>? savedSmsMcp;

  Json _smsSummary() => {
    'id': 'sms',
    'name': '短信助手',
    'description': '处理短信筛选与规则管理',
    'routingHint': 'Route SMS questions to sms.',
    'triggers': ['chat', 'background'],
    'enabled': smsEnabled,
    'executionPolicy': {'stateless': true, 'parallelAllowed': true},
    'hasUserInstructions': true,
    'capabilities': {
      'tools': [
        {
          'name': 'sms_query',
          'description': '查询短信记录',
          'triggers': ['chat'],
        },
      ],
      'skills': <Json>[],
      'mcp': [
        for (final name in smsMcp)
          {'name': name, 'description': 'Docs MCP', 'transport': 'http'},
      ],
    },
    'editability': {
      'enabled': 'editable',
      'systemPrompts': 'readonly',
      'userInstructions': 'editable',
      'tools': 'readonly',
      'skills': 'readonly',
      'mcp': 'editable',
    },
  };

  Json _habitsSummary() => {
    'id': 'habits',
    'name': '习惯归纳助手',
    'description': '后台定期归纳长期习惯',
    'routingHint': null,
    'triggers': ['background'],
    'enabled': habitsEnabled,
    'executionPolicy': {'stateless': true, 'parallelAllowed': true},
    'hasUserInstructions': false,
    'capabilities': {
      'tools': [
        {
          'name': 'submit_habit_updates',
          'description': '提交习惯增量变更',
          'triggers': ['background'],
        },
      ],
      'skills': <Json>[],
      'mcp': <Json>[],
    },
    'editability': {
      'enabled': 'editable',
      'systemPrompts': 'readonly',
      'userInstructions': 'none',
      'tools': 'readonly',
      'skills': 'readonly',
      'mcp': 'readonly',
    },
  };

  @override
  Future<Json> get(String path, {Map<String, String>? query}) async {
    if (path == '/api/subagents') {
      return {
        'subagents': [_smsSummary(), _habitsSummary()],
      };
    }
    if (path == '/api/subagents/sms') {
      return {
        ..._smsSummary(),
        'prompts': [
          {
            'key': 'chat',
            'label': '聊天路由任务提示词',
            'trigger': 'chat',
            'source': 'builtin',
            'sourcePath': 'prompts/subagents/sms-chat.md',
            'editable': false,
            'content': 'SMS_CHAT_PROMPT_BODY',
          },
        ],
        'userInstructions': {
          'path': 'subagents/sms/AGENTS.md',
          'instructions': smsInstructions,
          'includes': <Json>[],
          'habits': [
            {
              'id': 'h1',
              'text': '快递取件码提醒',
              'source': 'manual',
            },
          ],
          'unconsolidatedFeedbackCount': 0,
        },
      };
    }
    if (path == '/api/subagents/habits') {
      return {
        ..._habitsSummary(),
        'prompts': [
          {
            'key': 'consolidate',
            'label': '行为习惯归纳提示词',
            'trigger': 'background',
            'source': 'builtin',
            'sourcePath': 'prompts/habits/consolidate.md',
            'editable': false,
            'content': 'HABIT_PROMPT_BODY',
          },
        ],
        'userInstructions': null,
      };
    }
    if (path == '/api/subagents/sms/mcp') {
      return {
        'subagentId': 'sms',
        'editable': true,
        'servers': [
          {
            'name': 'docs',
            'transport': 'http',
            'description': 'Docs MCP',
            'globalEnabled': true,
            'status': 'connected',
            'toolCount': 2,
            'defaultEnabled': false,
            'enabled': smsMcp.contains('docs'),
            'effectiveEnabled': smsMcp.contains('docs'),
          },
        ],
        'enabledServers': List<String>.from(smsMcp),
      };
    }
    if (path == '/api/subagents/habits/mcp') {
      return {
        'subagentId': 'habits',
        'editable': false,
        'servers': <Json>[],
        'enabledServers': <String>[],
      };
    }
    throw UnimplementedError('Unexpected GET $path');
  }

  @override
  Future<Json> put(String path, Json body) async {
    if (path == '/api/subagents/sms/mcp') {
      final servers = (body['servers'] as List).cast<String>();
      smsMcp
        ..clear()
        ..addAll(servers);
      savedSmsMcp = List<String>.from(servers);
      return await get('/api/subagents/sms/mcp');
    }
    if (path == '/api/information/preferences') {
      smsInstructions = body['instructions'] as String;
      savedSmsInstructions = smsInstructions;
      return {
        'instructions': smsInstructions,
        'includes': <Json>[],
        'habits': [
          {'id': 'h1', 'text': '快递取件码提醒', 'source': 'manual'},
        ],
        'unconsolidatedFeedbackCount': 0,
      };
    }
    throw UnimplementedError('Unexpected PUT $path');
  }

  @override
  Future<Json> patch(String path, Json body) async {
    if (path == '/api/subagents/sms') {
      smsEnabled = body['enabled'] == true;
      return await get('/api/subagents/sms');
    }
    if (path == '/api/subagents/habits') {
      habitsEnabled = body['enabled'] == true;
      return await get('/api/subagents/habits');
    }
    throw UnimplementedError('Unexpected PATCH $path');
  }
}

void main() {
  testWidgets(
    'settings opens subagents, edits sms instructions and toggles MCP, habits stays readonly',
    (tester) async {
      final api = _FakeSubagentsApi();
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
      await tester.tap(find.text('Subagent'));
      await tester.pumpAndSettle();

      expect(find.text('短信助手'), findsOneWidget);
      expect(find.text('习惯归纳助手'), findsOneWidget);

      // Toggle sms switch directly on list card
      expect(api.smsEnabled, isFalse);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(api.smsEnabled, isTrue);

      // Open sms detail
      await tester.tap(find.text('短信助手'));
      await tester.pumpAndSettle();
      expect(find.text('启用'), findsOneWidget);

      // Enable docs MCP for sms
      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();
      expect(api.savedSmsMcp, ['docs']);

      // Edit & save sms domain instructions
      await tester.scrollUntilVisible(
        find.text('保存指令'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.byType(TextField),
        'Updated SMS alert rules',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存指令'));
      await tester.pumpAndSettle();
      expect(api.savedSmsInstructions, 'Updated SMS alert rules');

      // Expand builtin tools & prompts
      await tester.scrollUntilVisible(
        find.text('聊天路由任务提示词'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('聊天路由任务提示词'));
      await tester.pumpAndSettle();
      expect(find.text('SMS_CHAT_PROMPT_BODY'), findsOneWidget);

      // Back to list -> MCP badge updated to MCP 1
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('MCP 1'), findsOneWidget);

      // Open habits -> readonly MCP notice
      await tester.tap(find.text('习惯归纳助手'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不支持绑定外部 MCP 服务'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );
}
