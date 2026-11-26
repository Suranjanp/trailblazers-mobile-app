import 'package:flutter_test/flutter_test.dart';
import 'package:test_ap_1/services/dashboard_calendar_cache.dart';

void main() {
  final cache = DashboardCalendarCache.instance;

  // Reset the singleton before and after each test.
  setUp(() {
    cache.clear();
  });

  tearDown(() {
    cache.clear();
  });

  group('DashboardCalendarCache state', () {
    test('exposes the same shared instance', () {
      expect(identical(cache, DashboardCalendarCache.instance), isTrue);
    });

    test('cleared cache has no events or refresh timestamp', () {
      expect(cache.events, isEmpty);
      expect(cache.loadedAt, isNull);
    });

    test('update stores events in their original order', () {
      final events = <Map<String, dynamic>>[
        {
          'id': 'event-1',
          'summary': 'Morning class',
          'start': '2026-11-25T09:00:00',
        },
        {
          'id': 'event-2',
          'summary': 'Team meeting',
          'start': '2026-11-25T14:00:00',
        },
      ];

      cache.update(events);

      expect(cache.events, events);
      expect(cache.events.map((event) => event['id']).toList(), [
        'event-1',
        'event-2',
      ]);
    });

    test('update replaces previous events instead of appending', () {
      cache.update([
        {'id': 'old-event', 'summary': 'Old event'},
      ]);

      cache.update([
        {'id': 'new-event', 'summary': 'New event'},
      ]);

      expect(cache.events, [
        {'id': 'new-event', 'summary': 'New event'},
      ]);
    });

    test('update records a timestamp within the update interval', () {
      final before = DateTime.now();

      cache.update([
        {'id': 'event-1'},
      ]);

      final after = DateTime.now();
      final loadedAt = cache.loadedAt;

      expect(loadedAt, isNotNull);
      expect(loadedAt!.isBefore(before), isFalse);
      expect(loadedAt.isAfter(after), isFalse);
    });

    test('reading events does not change the refresh timestamp', () {
      cache.update([
        {'id': 'event-1'},
      ]);
      final originalTimestamp = cache.loadedAt;

      final firstRead = cache.events;
      final secondRead = cache.events;

      expect(firstRead, secondRead);
      expect(cache.loadedAt, originalTimestamp);
    });

    test('an empty update clears old events but records a refresh', () {
      cache.update([
        {'id': 'old-event'},
      ]);

      cache.update([]);

      expect(cache.events, isEmpty);
      expect(cache.loadedAt, isNotNull);
    });

    test('clear removes events and resets the timestamp', () {
      cache.update([
        {'id': 'event-1'},
        {'id': 'event-2'},
      ]);

      cache.clear();

      expect(cache.events, isEmpty);
      expect(cache.loadedAt, isNull);
    });

    test('clear can be called repeatedly', () {
      cache.clear();
      cache.clear();

      expect(cache.events, isEmpty);
      expect(cache.loadedAt, isNull);
    });

    test('cache can be populated again after clearing', () {
      cache.update([
        {'id': 'old-event'},
      ]);
      cache.clear();

      cache.update([
        {'id': 'new-event'},
      ]);

      expect(cache.events, [
        {'id': 'new-event'},
      ]);
      expect(cache.loadedAt, isNotNull);
    });
  });

  group('DashboardCalendarCache defensive copies', () {
    test('changing the original list does not change cached events', () {
      final input = <Map<String, dynamic>>[
        {'id': 'event-1'},
      ];

      cache.update(input);

      input.add({'id': 'event-2'});
      input.removeAt(0);

      expect(cache.events, [
        {'id': 'event-1'},
      ]);
    });

    test('changing an original map does not change cached fields', () {
      final event = <String, dynamic>{
        'id': 'event-1',
        'summary': 'Original title',
      };

      cache.update([event]);

      event['summary'] = 'Changed title';
      event['newField'] = true;
      event.remove('id');

      expect(cache.events, [
        {'id': 'event-1', 'summary': 'Original title'},
      ]);
    });

    test('changing a returned list does not change the cache', () {
      cache.update([
        {'id': 'event-1'},
      ]);

      final returned = cache.events;
      returned.clear();
      returned.add({'id': 'external-event'});

      expect(cache.events, [
        {'id': 'event-1'},
      ]);
    });

    test('changing a returned map does not change cached fields', () {
      cache.update([
        {'id': 'event-1', 'summary': 'Original title'},
      ]);

      final returned = cache.events;
      returned.first['summary'] = 'Changed title';
      returned.first.remove('id');

      expect(cache.events, [
        {'id': 'event-1', 'summary': 'Original title'},
      ]);
    });

    test('each read returns a new list and new top-level maps', () {
      cache.update([
        {'id': 'event-1'},
      ]);

      final firstRead = cache.events;
      final secondRead = cache.events;

      expect(firstRead, secondRead);
      expect(identical(firstRead, secondRead), isFalse);
      expect(identical(firstRead.first, secondRead.first), isFalse);
    });
  });

  group('DashboardCalendarCache notifications', () {
    test('update notifies once after events and timestamp are available', () {
      var notifications = 0;
      List<Map<String, dynamic>>? observedEvents;
      DateTime? observedTimestamp;

      void listener() {
        notifications++;
        observedEvents = cache.events;
        observedTimestamp = cache.loadedAt;
      }

      cache.addListener(listener);

      try {
        cache.update([
          {'id': 'event-1'},
        ]);

        expect(notifications, 1);
        expect(observedEvents, [
          {'id': 'event-1'},
        ]);
        expect(observedTimestamp, isNotNull);
        expect(observedTimestamp, cache.loadedAt);
      } finally {
        cache.removeListener(listener);
      }
    });

    test('empty update still notifies listeners', () {
      var notifications = 0;

      void listener() => notifications++;

      cache.addListener(listener);

      try {
        cache.update([]);

        expect(notifications, 1);
        expect(cache.events, isEmpty);
        expect(cache.loadedAt, isNotNull);
      } finally {
        cache.removeListener(listener);
      }
    });

    test('clear notifies after events and timestamp are reset', () {
      cache.update([
        {'id': 'event-1'},
      ]);

      var notifications = 0;
      List<Map<String, dynamic>>? observedEvents;
      DateTime? observedTimestamp = cache.loadedAt;

      void listener() {
        notifications++;
        observedEvents = cache.events;
        observedTimestamp = cache.loadedAt;
      }

      cache.addListener(listener);

      try {
        cache.clear();

        expect(notifications, 1);
        expect(observedEvents, isEmpty);
        expect(observedTimestamp, isNull);
      } finally {
        cache.removeListener(listener);
      }
    });

    test('clearing an already empty cache still notifies', () {
      var notifications = 0;

      void listener() => notifications++;

      cache.addListener(listener);

      try {
        cache.clear();

        expect(notifications, 1);
      } finally {
        cache.removeListener(listener);
      }
    });

    test('reading or modifying returned copies does not notify', () {
      cache.update([
        {'id': 'event-1'},
      ]);

      var notifications = 0;

      void listener() => notifications++;

      cache.addListener(listener);

      try {
        final returned = cache.events;
        returned.first['id'] = 'external-change';
        returned.clear();

        expect(notifications, 0);
        expect(cache.events, [
          {'id': 'event-1'},
        ]);
      } finally {
        cache.removeListener(listener);
      }
    });

    test('removed listeners receive no further notifications', () {
      var notifications = 0;

      void listener() => notifications++;

      cache.addListener(listener);
      cache.removeListener(listener);

      cache.update([
        {'id': 'event-1'},
      ]);
      cache.clear();

      expect(notifications, 0);
    });
  });
}