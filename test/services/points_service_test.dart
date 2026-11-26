import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_ap_1/services/points_service.dart';

void main() {
  final service = PointsService.instance;

  group('To-do scoring', () {
    // Check the actual scoring requirements, not just the service constants.
    const expectedRewards = {1: 10, 2: 15, 3: 25, 4: 40, 5: 50};

    for (final entry in expectedRewards.entries) {
      test('importance ${entry.key} awards ${entry.value} points', () {
        expect(
          service.pointsForActivity(
            PointsActivityType.todo,
            importance: entry.key,
          ),
          entry.value,
        );
      });
    }

    test('default importance uses the first reward tier', () {
      expect(service.pointsForActivity(PointsActivityType.todo), 10);
    });

    test('importance below one is clamped to the first tier', () {
      for (final importance in [-100, -1, 0]) {
        expect(
          service.pointsForActivity(
            PointsActivityType.todo,
            importance: importance,
          ),
          10,
          reason: 'Importance $importance should use tier one.',
        );
      }
    });

    test('importance above five is clamped to the highest tier', () {
      for (final importance in [6, 10, 100]) {
        expect(
          service.pointsForActivity(
            PointsActivityType.todo,
            importance: importance,
          ),
          50,
          reason: 'Importance $importance should use tier five.',
        );
      }
    });
  });

  group('Other activity scoring', () {
    const expectedRewards = {
      PointsActivityType.workout: 40,
      PointsActivityType.healthGoal: 20,
      PointsActivityType.scheduleCommitment: 25,
      PointsActivityType.dailyGoals: 30,
    };

    for (final entry in expectedRewards.entries) {
      test('${entry.key.name} awards ${entry.value} points', () {
        expect(service.pointsForActivity(entry.key), entry.value);
      });

      test('${entry.key.name} reward does not depend on to-do importance', () {
        for (final importance in [-1, 1, 3, 5, 100]) {
          expect(
            service.pointsForActivity(entry.key, importance: importance),
            entry.value,
          );
        }
      });
    }
  });

  group('Activity document IDs', () {
    test('creates the expected stable key for a known activity', () {
      // UTF-8 "task-123" becomes "dGFzay0xMjM" without Base64 padding.
      expect(
        service.activityDocumentId(PointsActivityType.todo, 'task-123'),
        'todo_dGFzay0xMjM',
      );
    });

    test('repeated calls for the same activity produce the same key', () {
      final first = service.activityDocumentId(
        PointsActivityType.workout,
        'workout-42',
      );
      final second = service.activityDocumentId(
        PointsActivityType.workout,
        'workout-42',
      );

      expect(first, second);
    });

    test('trims surrounding whitespace before generating the key', () {
      final clean = service.activityDocumentId(
        PointsActivityType.todo,
        'task-123',
      );
      final padded = service.activityDocumentId(
        PointsActivityType.todo,
        '  task-123 \n',
      );

      expect(padded, clean);
    });

    test('different source IDs produce different keys', () {
      expect(
        service.activityDocumentId(PointsActivityType.todo, 'task-1'),
        isNot(service.activityDocumentId(PointsActivityType.todo, 'task-2')),
      );
    });

    test('equal source IDs remain distinct across activity categories', () {
      final keys = PointsActivityType.values
          .map((type) => service.activityDocumentId(type, 'same-source'))
          .toSet();

      expect(keys, hasLength(PointsActivityType.values.length));
    });

    test('preserves meaningful internal spaces and letter case', () {
      final sourceIds = ['task one', 'taskone', 'Task one'];

      final keys = sourceIds
          .map((id) => service.activityDocumentId(PointsActivityType.todo, id))
          .toSet();

      expect(keys, hasLength(sourceIds.length));
    });

    test('encodes special characters without path separators or padding', () {
      final key = service.activityDocumentId(
        PointsActivityType.scheduleCommitment,
        'calendar/event?name=A+B&value=1#section',
      );

      expect(key, startsWith('scheduleCommitment_'));
      expect(key, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(key.contains('/'), isFalse);
      expect(key.contains('='), isFalse);
    });

    test('Unicode source IDs survive encoding without losing characters', () {
      const source = 'व्यायाम 🏃 / session-42';
      const type = PointsActivityType.workout;

      final key = service.activityDocumentId(type, source);
      final encodedPart = key.substring('${type.name}_'.length);

      // Restore omitted padding before decoding the generated key.
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(encodedPart)),
      );

      expect(decoded, source);
    });
  });

  group('Category labels', () {
    const expectedLabels = {
      'todo': 'To-do tasks',
      'workout': 'Workouts',
      'healthGoal': 'Health goals',
      'scheduleCommitment': 'Schedule commitments',
      'dailyGoals': 'Daily goals',
    };

    for (final entry in expectedLabels.entries) {
      test('${entry.key} has its expected display label', () {
        expect(service.categoryLabel(entry.key), entry.value);
      });
    }

    test('unknown or missing category names use the fallback label', () {
      for (final category in ['', 'unknown', 'futureCategory']) {
        expect(service.categoryLabel(category), 'Other activities');
      }
    });
  });

  group('PointsAwardResult', () {
    test('represents a newly awarded activity', () {
      const result = PointsAwardResult(
        awarded: true,
        points: 40,
        totalPoints: 140,
      );

      expect(result.awarded, isTrue);
      expect(result.points, 40);
      expect(result.totalPoints, 140);
    });

    test('represents a duplicate without adding more points', () {
      // This checks the result object. Database duplicate prevention is
      // a separate transaction test.
      const result = PointsAwardResult(
        awarded: false,
        points: 0,
        totalPoints: 140,
      );

      expect(result.awarded, isFalse);
      expect(result.points, 0);
      expect(result.totalPoints, 140);
    });
  });

  group('PointsReport', () {
    test('retains report boundaries, totals and activity count', () {
      final start = DateTime(2026, 11, 25);
      final end = DateTime(2026, 11, 26);

      final report = PointsReport(
        start: start,
        end: end,
        totalPoints: 65,
        activityCount: 2,
        pointsByCategory: const {'todo': 25, 'workout': 40},
      );

      expect(report.start, start);
      expect(report.end, end);
      expect(report.totalPoints, 65);
      expect(report.activityCount, 2);
      expect(report.pointsByCategory, {'todo': 25, 'workout': 40});
    });

    test('returns the points for a category that exists', () {
      final report = PointsReport(
        start: DateTime(2026, 11, 25),
        end: DateTime(2026, 11, 26),
        totalPoints: 65,
        activityCount: 2,
        pointsByCategory: const {'todo': 25, 'workout': 40},
      );

      expect(report.pointsFor('todo'), 25);
      expect(report.pointsFor('workout'), 40);
    });

    test('returns zero for categories absent from a populated report', () {
      final report = PointsReport(
        start: DateTime(2026, 11, 25),
        end: DateTime(2026, 11, 26),
        totalPoints: 40,
        activityCount: 1,
        pointsByCategory: const {'workout': 40},
      );

      expect(report.pointsFor('todo'), 0);
      expect(report.pointsFor('unknown'), 0);
    });

    test('supports an empty report', () {
      final report = PointsReport(
        start: DateTime(2026, 11, 25),
        end: DateTime(2026, 11, 26),
        totalPoints: 0,
        activityCount: 0,
        pointsByCategory: const {},
      );

      expect(report.totalPoints, 0);
      expect(report.activityCount, 0);
      expect(report.pointsByCategory, isEmpty);

      for (final type in PointsActivityType.values) {
        expect(report.pointsFor(type.name), 0);
      }
    });
  });

  group('Report date validation', () {
    // Invalid ranges are rejected before the service accesses Firebase,
    // so these tests do not require Firebase initialization.
    test('rejects a report whose end equals its start', () async {
      final date = DateTime(2026, 11, 25);

      await expectLater(
        service.getReport(start: date, end: date),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a report whose end precedes its start', () async {
      await expectLater(
        service.getReport(
          start: DateTime(2026, 11, 26),
          end: DateTime(2026, 11, 25),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
