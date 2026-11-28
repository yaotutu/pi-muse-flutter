import 'package:material_ui/material_ui.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_muse_flutter/src/features/agenda/agenda.dart';
import 'package:pi_muse_flutter/src/network/api.dart';
import 'package:pi_muse_flutter/src/shared/workspace_events.dart';

import '../../support/agenda_test_api.dart';

void main() {
  group('agenda moment', () {
    test('keeps the calendar day of a date-only value', () {
      final moment = parseAgendaMoment('2026-03-08');
      expect(moment, isNotNull);
      expect(moment!.dateOnly, isTrue);
      expect(moment.wallClock, DateTime(2026, 3, 8));
      expect(moment.hasTime, isFalse);
    });

    test('keeps the wall clock and offset of a timestamp', () {
      final moment = parseAgendaMoment(
        '2026-03-08T09:30:00+08:00',
        zoneName: 'Asia/Shanghai',
      );
      expect(moment!.wallClock, DateTime(2026, 3, 8, 9, 30));
      expect(moment.hasTime, isTrue);
      expect(moment.offset, const Duration(hours: 8));
      expect(moment.zoneLabel, 'Asia/Shanghai');
    });

    test('reports the offset when the server does not name a zone', () {
      expect(
        parseAgendaMoment('2026-03-08T09:30:00+08:00')!.zoneLabel,
        'UTC+08:00',
      );
      expect(
        parseAgendaMoment('2026-03-08T09:30:00-05:00')!.zoneLabel,
        'UTC-05:00',
      );
    });

    test('converts a UTC timestamp into the server timezone', () {
      final moment = parseAgendaMoment(
        '2026-03-08T01:00:00Z',
        zoneName: 'Asia/Shanghai',
      );
      expect(moment!.wallClock, DateTime(2026, 3, 8, 9));
      expect(moment.zoneLabel, 'Asia/Shanghai');
      expect(moment.instant, DateTime.utc(2026, 3, 8, 1));
    });

    test(
      'falls back to the device timezone when the server zone is unknown',
      () {
        final moment = parseAgendaMoment(
          '2026-03-08T01:00:00Z',
          zoneName: 'Invalid/Zone',
        );
        expect(moment!.wallClock, DateTime.utc(2026, 3, 8, 1).toLocal());
        expect(moment.zoneLabel, startsWith('本机'));
      },
    );

    test('applies the correct IANA offset in winter and summer', () {
      final winter = agendaTimeInZone(
        DateTime.utc(2026, 1, 15, 14),
        'America/New_York',
      );
      final summer = agendaTimeInZone(
        DateTime.utc(2026, 7, 15, 13),
        'America/New_York',
      );
      expect(winter?.hour, 9);
      expect(summer?.hour, 9);
      expect(winter?.timeZoneOffset, const Duration(hours: -5));
      expect(summer?.timeZoneOffset, const Duration(hours: -4));
    });

    test('rejects values that are not dates', () {
      expect(parseAgendaMoment('not-a-date'), isNull);
      expect(parseAgendaMoment(null), isNull);
      expect(parseAgendaMoment('2026-02-30'), isNull);
    });

    test(
      'serializes a picked local moment for interpretation by the server',
      () {
        final moment = DateTime(2026, 3, 8, 9, 30);
        expect(
          formatAgendaLocalTimestamp(
            moment,
            const TimeOfDay(hour: 9, minute: 30),
          ),
          '2026-03-08T09:30',
        );
        expect(formatAgendaDate(DateTime(2026, 3, 8)), '2026-03-08');
      },
    );
  });

  group('agenda item', () {
    test('reads schedule, due and reminders from the contract', () {
      final item = AgendaItem.fromJson({
        'id': 'item',
        'title': '取快递',
        'notes': null,
        'schedule': {
          'type': 'date',
          'start': '2026-03-08',
          'timeZone': 'Asia/Shanghai',
        },
        'due': {'type': 'time', 'value': '2026-03-09T18:00:00+08:00'},
        'pinnedAt': null,
        'completedAt': null,
        'createdAt': '2026-03-01T00:00:00Z',
        'updatedAt': '2026-03-01T00:00:00Z',
        'reminders': [
          {
            'id': 'reminder',
            'kind': 'absolute',
            'fireAt': '2026-03-08T09:00:00+08:00',
            'status': 'pending',
            'triggeredAt': null,
          },
        ],
      });
      expect(item.schedule!.moment!.wallClock, DateTime(2026, 3, 8));
      expect(item.due!.moment!.wallClock, DateTime(2026, 3, 9, 18));
      expect(item.reminders.single.pending, isTrue);
      expect(item.completed, isFalse);
      expect(item.pinned, isFalse);
      expect(item.days(), [
        DateTime(2026, 3, 8),
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 8),
      ]);
    });

    test('skips items that do not carry an id', () {
      expect(AgendaItem.tryParse({'title': '缺少 ID'}), isNull);
      expect(AgendaItem.tryParse({'id': 'x', 'title': '有 ID'}), isNotNull);
    });

    test('counts the intermediate days of a multi-day schedule', () {
      final item = AgendaItem.fromJson({
        'id': 'item',
        'title': '出差',
        'schedule': {
          'type': 'time',
          'start': '2026-03-08T09:00:00+08:00',
          'end': '2026-03-10T18:00:00+08:00',
        },
        'reminders': <Json>[],
      });
      expect(item.scheduleDays(), [
        DateTime(2026, 3, 8),
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 10),
      ]);
    });

    test('the instance timezone decides the calendar day', () {
      final item = AgendaItem.fromJson({
        'id': 'item',
        'title': '提醒',
        'reminders': [
          {
            'id': 'reminder',
            'kind': 'absolute',
            'fireAt': '2026-03-08T23:30:00Z',
            'status': 'pending',
          },
        ],
      });
      // 23:30Z 在 UTC+8 是次日 07:30，日历归属按实例时区。
      expect(item.reminderDays(instanceZone: 'Asia/Shanghai'), [
        DateTime(2026, 3, 9),
      ]);
      expect(item.reminderDays(instanceZone: 'UTC'), [DateTime(2026, 3, 8)]);
    });
  });

  group('agenda client', () {
    test('learns the instance timezone from the health endpoint', () async {
      final api = AgendaTestApi()..healthTimeZone = 'Asia/Shanghai';
      final client = AgendaClient(api);

      await client.list();

      expect(client.instanceZone, 'Asia/Shanghai');
    });

    test('lists with the contract filters and keeps undated items', () async {
      final api = AgendaTestApi()
        ..items = [
          {'id': 'a', 'title': '没有时间的事项'},
        ];
      final client = AgendaClient(api);

      final items = await client.list(
        scope: AgendaScope.unfinished,
        query: ' 快递 ',
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 4, 1),
      );

      expect(items.single.title, '没有时间的事项');
      expect(api.agendaQueries.single, {
        'status': 'open',
        'q': '快递',
        'from': '2026-03-01',
        'to': '2026-04-01',
      });
    });

    test('creates an item with only the given fields', () async {
      final api = AgendaTestApi();
      final client = AgendaClient(api);

      await client.create(
        title: '取快递',
        schedule: {'type': 'date', 'start': '2026-03-08'},
      );

      expect(api.agendaWrites.single.$1, '/api/agenda/items');
      expect(api.agendaWrites.single.$2, {
        'title': '取快递',
        'schedule': {'type': 'date', 'start': '2026-03-08'},
      });
    });

    test('patches only the changed fields', () async {
      final api = AgendaTestApi()
        ..items = [
          {'id': 'a', 'title': '取快递'},
        ];
      final client = AgendaClient(api);

      await client.update('a', title: '取快递', completed: true, pinned: true);

      expect(api.agendaWrites.single.$2, {
        'title': '取快递',
        'completed': true,
        'pinned': true,
      });
    });

    test('clears a schedule with an explicit null', () async {
      final api = AgendaTestApi()
        ..items = [
          {'id': 'a', 'title': '取快递'},
        ];
      final client = AgendaClient(api);

      await client.update('a', clearSchedule: true);

      expect(api.agendaWrites.single.$2, {'schedule': null});
    });

    test('writes reminders on the item and returns the updated item', () async {
      final api = AgendaTestApi()
        ..items = [
          {'id': 'a', 'title': '取快递', 'reminders': <Json>[]},
        ];
      final client = AgendaClient(api);

      final item = await client.addReminder(
        'a',
        date: '2026-03-08',
        time: '09:00',
      );
      await client.updateReminder(
        'a',
        'reminder',
        date: '2026-03-08',
        time: '09:30',
      );
      await client.deleteReminder('a', 'reminder');

      expect(api.agendaWrites.map((write) => write.$1), [
        '/api/agenda/items/a/reminders',
        '/api/agenda/items/a/reminders/reminder',
        '/api/agenda/items/a/reminders/reminder',
      ]);
      expect(api.agendaWrites.first.$2, {
        'kind': 'absolute',
        'date': '2026-03-08',
        'time': '09:00',
      });
      expect(item.reminders.single.id, 'reminder');
    });
  });

  group('agenda controller', () {
    test('refreshes when the connection reports an agenda update', () async {
      final api = AgendaTestApi();
      final events = StreamController<WorkspaceEvent>();
      final controller = AgendaController(
        client: AgendaClient(api),
        events: events.stream,
      );
      addTearDown(controller.dispose);
      addTearDown(events.close);

      await controller.refresh();
      expect(api.agendaQueries.length, 2);

      events.add((name: 'agenda_updated', data: {'instanceId': 'x'}));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(api.agendaQueries.length, 4);
    });

    test('ignores unrelated workspace events', () async {
      final api = AgendaTestApi();
      final events = StreamController<WorkspaceEvent>();
      final controller = AgendaController(
        client: AgendaClient(api),
        events: events.stream,
      );
      addTearDown(controller.dispose);
      addTearDown(events.close);

      await controller.refresh();
      events.add((name: 'session_status_updated', data: {'instanceId': 'x'}));
      await Future<void>.delayed(Duration.zero);

      expect(api.agendaQueries.length, 2);
    });

    test(
      'an ambiguous write failure rereads the state without resending',
      () async {
        final api = AgendaTestApi()
          ..items = [
            {'id': 'a', 'title': '取快递'},
          ]
          ..agendaWriteFailure = const ApiException(0);
        final events = StreamController<WorkspaceEvent>();
        final controller = AgendaController(
          client: AgendaClient(api),
          events: events.stream,
        );
        addTearDown(controller.dispose);
        addTearDown(events.close);
        await controller.refresh();
        final before = api.agendaQueries.length;

        final item = await controller.setCompleted(
          (await controller.read('a'))!,
          true,
        );

        expect(item, isNull);
        expect(controller.notice, contains('未确认'));
        // 只写了一次，写失败后回读权威状态，不重发写请求。
        expect(
          api.agendaWrites.where(
            (write) => write.$1.contains('/api/agenda/items/a'),
          ),
          hasLength(1),
        );
        expect(api.agendaQueries.length, greaterThan(before));
      },
    );

    test('a rejected write keeps the server error', () async {
      final api = AgendaTestApi()
        ..items = [
          {'id': 'a', 'title': '取快递'},
        ]
        ..agendaWriteFailure = const ApiException(400, code: 'INVALID_INPUT');
      final events = StreamController<WorkspaceEvent>();
      final controller = AgendaController(
        client: AgendaClient(api),
        events: events.stream,
      );
      addTearDown(controller.dispose);
      addTearDown(events.close);

      final item = await controller.setPinned(
        (await controller.read('a'))!,
        true,
      );

      expect(item, isNull);
      expect(controller.notice, '内容格式无效或超出长度限制');
    });
  });
}
