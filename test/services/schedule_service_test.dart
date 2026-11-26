import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_ap_1/services/schedule_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageKey = 'trailblazer-schedule';

  // Use fresh in-memory storage for every test.
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ScheduleService.loadEntries', () {
    test('returns an empty list when no schedule has been saved', () async {
      expect(await ScheduleService.loadEntries(), isEmpty);
    });

    test('returns an empty list for an empty stored string', () async {
      SharedPreferences.setMockInitialValues({storageKey: ''});

      expect(await ScheduleService.loadEntries(), isEmpty);
    });

    test('loads saved entries and preserves their order', () async {
      final entries = <Map<String, dynamic>>[
        {
          'id': 'class-1',
          'title': 'Morning class',
          'start': '2026-11-25T09:00:00',
        },
        {'id': 'workout-1', 'title': 'Workout', 'start': '2026-11-25T17:00:00'},
      ];

      SharedPreferences.setMockInitialValues({storageKey: jsonEncode(entries)});

      final loaded = await ScheduleService.loadEntries();

      expect(loaded, entries);
      expect(loaded.map((entry) => entry['id']).toList(), [
        'class-1',
        'workout-1',
      ]);
    });

    test('returns an empty list for a saved empty JSON list', () async {
      SharedPreferences.setMockInitialValues({storageKey: '[]'});

      expect(await ScheduleService.loadEntries(), isEmpty);
    });

    // A valid JSON value is not necessarily a valid schedule list.
    final nonListValues = <String, Object?>{
      'object': {'title': 'Not a list'},
      'string': 'Not a list',
      'number': 42,
      'boolean': true,
      'null': null,
    };

    for (final entry in nonListValues.entries) {
      test('returns an empty list for a JSON ${entry.key}', () async {
        SharedPreferences.setMockInitialValues({
          storageKey: jsonEncode(entry.value),
        });

        expect(await ScheduleService.loadEntries(), isEmpty);
      });
    }

    for (final malformed in [
      'not JSON',
      '[{"title": "Missing closing brackets"',
      '[1, 2,]',
      '   ',
    ]) {
      test('handles malformed JSON: ${jsonEncode(malformed)}', () async {
        SharedPreferences.setMockInitialValues({storageKey: malformed});

        expect(await ScheduleService.loadEntries(), isEmpty);
      });
    }

    test('ignores non-map elements while retaining valid entries', () async {
      SharedPreferences.setMockInitialValues({
        storageKey: jsonEncode([
          {'id': 'first', 'title': 'Class'},
          null,
          42,
          'invalid entry',
          true,
          ['nested list'],
          {'id': 'second', 'title': 'Study'},
        ]),
      });

      expect(await ScheduleService.loadEntries(), [
        {'id': 'first', 'title': 'Class'},
        {'id': 'second', 'title': 'Study'},
      ]);
    });

    test('returns an empty list when no elements are maps', () async {
      SharedPreferences.setMockInitialValues({
        storageKey: jsonEncode([null, 1, false, 'text', []]),
      });

      expect(await ScheduleService.loadEntries(), isEmpty);
    });

    test(
      'retains map-shaped entries without enforcing a field schema',
      () async {
        // This service stores records; screen/model validation is separate.
        SharedPreferences.setMockInitialValues({
          storageKey: jsonEncode([
            {},
            {'customField': 'custom value'},
          ]),
        });

        expect(await ScheduleService.loadEntries(), [
          <String, dynamic>{},
          {'customField': 'custom value'},
        ]);
      },
    );

    test('loading entries does not rewrite the saved data', () async {
      const raw = '[{"id":"event-1","title":"Class"}]';

      SharedPreferences.setMockInitialValues({storageKey: raw});

      await ScheduleService.loadEntries();

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(storageKey), raw);
    });

    test('modifying loaded entries does not change persisted data', () async {
      SharedPreferences.setMockInitialValues({
        storageKey: jsonEncode([
          {'id': 'event-1', 'title': 'Original title'},
        ]),
      });

      final loaded = await ScheduleService.loadEntries();
      loaded.first['title'] = 'Changed locally';
      loaded.add({'id': 'event-2'});

      // Changes only persist when saveEntries is explicitly called.
      expect(await ScheduleService.loadEntries(), [
        {'id': 'event-1', 'title': 'Original title'},
      ]);
    });
  });

  group('ScheduleService.saveEntries', () {
    test('writes JSON under the existing schedule storage key', () async {
      final entries = <Map<String, dynamic>>[
        {'id': 'event-1', 'title': 'Class'},
      ];

      await ScheduleService.saveEntries(entries);

      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(storageKey);

      expect(saved, isNotNull);
      expect(jsonDecode(saved!), entries);
    });

    test('replaces the previous schedule instead of appending', () async {
      await ScheduleService.saveEntries([
        {'id': 'old-event', 'title': 'Old event'},
      ]);

      await ScheduleService.saveEntries([
        {'id': 'new-event', 'title': 'New event'},
      ]);

      expect(await ScheduleService.loadEntries(), [
        {'id': 'new-event', 'title': 'New event'},
      ]);
    });

    test('saving an empty list clears previously saved entries', () async {
      await ScheduleService.saveEntries([
        {'id': 'event-1'},
      ]);

      await ScheduleService.saveEntries([]);

      expect(await ScheduleService.loadEntries(), isEmpty);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(storageKey), '[]');
    });

    test('preserves unrelated preferences', () async {
      SharedPreferences.setMockInitialValues({
        'settings_dark_mode': true,
        'unrelated_setting': 'keep me',
      });

      await ScheduleService.saveEntries([
        {'id': 'event-1'},
      ]);

      final preferences = await SharedPreferences.getInstance();

      expect(preferences.getBool('settings_dark_mode'), isTrue);
      expect(preferences.getString('unrelated_setting'), 'keep me');
    });

    test('saving does not modify the caller’s entries', () async {
      final entries = <Map<String, dynamic>>[
        {
          'id': 'event-1',
          'title': 'Class',
          'days': ['Monday', 'Wednesday'],
        },
      ];

      // Take a separate JSON snapshot before passing the list to the service.
      final original = jsonDecode(jsonEncode(entries));

      await ScheduleService.saveEntries(entries);

      expect(entries, original);
    });

    test(
      'rejects non-JSON data without replacing the saved schedule',
      () async {
        final original = <Map<String, dynamic>>[
          {'id': 'existing-event', 'title': 'Keep this event'},
        ];

        await ScheduleService.saveEntries(original);

        // DateTime must be converted to a string or another JSON-safe value
        // by the caller before saving.
        await expectLater(
          ScheduleService.saveEntries([
            {'id': 'invalid-event', 'start': DateTime(2026, 11, 25)},
          ]),
          throwsA(isA<JsonUnsupportedObjectError>()),
        );

        expect(await ScheduleService.loadEntries(), original);
      },
    );
  });

  group('Schedule JSON round trips', () {
    test('preserves supported nested values and optional fields', () async {
      final entries = <Map<String, dynamic>>[
        {
          'id': 'event-1',
          'title': 'Workout',
          'completed': false,
          'importance': 3,
          'durationHours': 1.5,
          'location': null,
          'days': ['Monday', 'Wednesday'],
          'reminder': {'enabled': true, 'minutesBefore': 15},
        },
      ];

      await ScheduleService.saveEntries(entries);

      expect(await ScheduleService.loadEntries(), entries);
    });

    test('preserves Unicode, quotes, backslashes and newlines', () async {
      final entries = <Map<String, dynamic>>[
        {
          'id': 'event-1',
          'title': 'व्यायाम 🏃',
          'notes': 'Bring "water".\nMeet at C:\\Campus\\Gym.',
        },
      ];

      await ScheduleService.saveEntries(entries);

      expect(await ScheduleService.loadEntries(), entries);
    });

    test('preserves multiple entries through repeated save and load', () async {
      final entries = List<Map<String, dynamic>>.generate(
        100,
        (index) => {
          'id': 'event-$index',
          'title': 'Activity $index',
          'completed': index.isEven,
        },
      );

      await ScheduleService.saveEntries(entries);
      final firstLoad = await ScheduleService.loadEntries();

      await ScheduleService.saveEntries(firstLoad);
      final secondLoad = await ScheduleService.loadEntries();

      expect(firstLoad, entries);
      expect(secondLoad, entries);
    });
  });
}