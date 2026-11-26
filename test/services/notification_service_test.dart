import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:test_ap_1/services/notification_service.dart';

// Mock native plugins so tests never show notifications or permission dialogs.
class _MockNotifications extends Mock
    implements FlutterLocalNotificationsPlugin {}

class _MockAndroidNotifications extends Mock
    implements AndroidFlutterLocalNotificationsPlugin {}

class _MockIosNotifications extends Mock
    implements IOSFlutterLocalNotificationsPlugin {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockNotifications plugin;
  late _MockAndroidNotifications androidPlugin;
  late _MockIosNotifications iosPlugin;
  late NotificationService service;

  late tz.Location originalTimezone;
  late String deviceTimezone;
  late int timezoneLookups;

  // Record outgoing requests so their content can be checked.
  late List<Map<Symbol, dynamic>> shown;
  late List<Map<Symbol, dynamic>> scheduled;
  late List<int> cancelled;

  setUpAll(() {
    timezone_data.initializeTimeZones();

    // Mocktail needs fallback values for custom non-nullable arguments.
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(tz.TZDateTime(tz.UTC, 2030));
    registerFallbackValue(AndroidScheduleMode.inexactAllowWhileIdle);
  });

  setUp(() {
    originalTimezone = tz.local;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    plugin = _MockNotifications();
    androidPlugin = _MockAndroidNotifications();
    iosPlugin = _MockIosNotifications();

    deviceTimezone = 'America/Chicago';
    timezoneLookups = 0;
    shown = [];
    scheduled = [];
    cancelled = [];

    // Each test receives a fresh service instead of sharing singleton state.
    service = NotificationService.forTesting(
      plugin: plugin,
      loadTimezone: () async {
        timezoneLookups++;
        return deviceTimezone;
      },
    );

    when(
      () => plugin.initialize(
        settings: any(named: 'settings'),
        onDidReceiveNotificationResponse: any(
          named: 'onDidReceiveNotificationResponse',
        ),
      ),
    ).thenAnswer((_) async => true);

    when(
      () => plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >(),
    ).thenReturn(androidPlugin);

    when(
      () => plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >(),
    ).thenReturn(iosPlugin);

    when(() => androidPlugin.requestNotificationsPermission())
        .thenAnswer((_) async => true);

    when(
      () =>
          iosPlugin.requestPermissions(alert: true, badge: false, sound: true),
    ).thenAnswer((_) async => true);

    when(
      () => plugin.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((invocation) async {
      shown.add(Map<Symbol, dynamic>.from(invocation.namedArguments));
    });

    when(
      () => plugin.zonedSchedule(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        scheduledDate: any(named: 'scheduledDate'),
        notificationDetails: any(named: 'notificationDetails'),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((invocation) async {
      scheduled.add(Map<Symbol, dynamic>.from(invocation.namedArguments));
    });

    when(() => plugin.cancel(id: any(named: 'id')))
        .thenAnswer((invocation) async {
          cancelled.add(invocation.namedArguments[#id] as int);
        });

    when(() => plugin.cancelAll()).thenAnswer((_) async {});

    when(() => plugin.pendingNotificationRequests())
        .thenAnswer((_) async => <PendingNotificationRequest>[]);
  });

  tearDown(() {
    // Restore global settings so this file does not affect other tests.
    tz.setLocalLocation(originalTimezone);
    debugDefaultTargetPlatformOverride = null;
  });

  group('Initialization guards', () {
    test('starts uninitialized', () {
      expect(service.isInitialized, isFalse);
    });

    test(
      'all notification operations reject use before initialization',
      () async {
        final futureEvent = DateTime.now().add(const Duration(days: 2));

        final operations = <String, Future<dynamic> Function()>{
          'permissions': () => service.requestPermissions(),
          'show': () =>
              service.showNotification(id: 1, title: 'Test', body: 'Body'),
          'schedule': () => service.scheduleEventReminder(
            notificationId: 1,
            title: 'Test',
            eventStart: futureEvent,
          ),
          'schedule occurrences': () =>
              service.scheduleEventReminderOccurrences(
                firstNotificationId: 100,
                title: 'Test',
                eventStartTimes: [futureEvent],
              ),
          'cancel': () => service.cancelNotification(1),
          'cancel occurrences': () =>
              service.cancelEventReminderOccurrences(100),
          'cancel all': () => service.cancelAllNotifications(),
          'pending': () => service.getPendingNotifications(),
        };

        for (final operation in operations.entries) {
          await expectLater(
            operation.value(),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                contains('has not been initialized'),
              ),
            ),
            reason: '${operation.key} must require initialization.',
          );
        }

        verifyZeroInteractions(plugin);
      },
    );
  });

  group('Initialization', () {
    test('sets the device time zone and initializes only once', () async {
      await service.initialize();
      await service.initialize();

      expect(service.isInitialized, isTrue);
      expect(tz.local.name, 'America/Chicago');
      expect(timezoneLookups, 1);

      verify(
        () => plugin.initialize(
          settings: any(named: 'settings'),
          onDidReceiveNotificationResponse: any(
            named: 'onDidReceiveNotificationResponse',
          ),
        ),
      ).called(1);
    });

    test(
      'configures the launcher icon and defers Apple permission prompts',
      () async {
        await service.initialize();

        final settings =
            verify(
                  () => plugin.initialize(
                    settings: captureAny(named: 'settings'),
                    onDidReceiveNotificationResponse: any(
                      named: 'onDidReceiveNotificationResponse',
                    ),
                  ),
                ).captured.single
                as InitializationSettings;

        expect(settings.android!.defaultIcon, 'launcher_icon');
        expect(settings.iOS!.requestAlertPermission, isFalse);
        expect(settings.iOS!.requestBadgePermission, isFalse);
        expect(settings.iOS!.requestSoundPermission, isFalse);

        verifyNever(() => androidPlugin.requestNotificationsPermission());

        verifyNever(
          () => iosPlugin.requestPermissions(
            alert: true,
            badge: false,
            sound: true,
          ),
        );
      },
    );

    test('passes notification taps to the supplied callback', () async {
      NotificationResponse? received;

      await service.initialize(
        onNotificationTap: (response) => received = response,
      );

      final callback =
          verify(
                () => plugin.initialize(
                  settings: any(named: 'settings'),
                  onDidReceiveNotificationResponse: captureAny(
                    named: 'onDidReceiveNotificationResponse',
                  ),
                ),
              ).captured.single
              as DidReceiveNotificationResponseCallback;

      final response = NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 42,
        payload: 'event:42',
      );

      callback(response);

      expect(received, same(response));
    });

    test(
      'rejects an unknown time zone without initializing the plugin',
      () async {
        deviceTimezone = 'Invalid/TrailblazerZone';

        await expectLater(
          service.initialize(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('could not determine the device time zone'),
            ),
          ),
        );

        expect(service.isInitialized, isFalse);
        verifyZeroInteractions(plugin);

        // Retry with a valid zone already used successfully by other tests.
        deviceTimezone = 'America/Chicago';
        await service.initialize();

        expect(service.isInitialized, isTrue);
        expect(tz.local.name, 'America/Chicago');
        expect(timezoneLookups, 2);
      },
    );

    test('wraps a failed device time-zone lookup in a useful error', () async {
      service = NotificationService.forTesting(
        plugin: plugin,
        loadTimezone: () async {
          throw StateError('Device lookup failed');
        },
      );

      await expectLater(
        service.initialize(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Device lookup failed'),
          ),
        ),
      );

      expect(service.isInitialized, isFalse);
      verifyZeroInteractions(plugin);
    });

    test(
      'plugin initialization failure leaves the service uninitialized',
      () async {
        final failure = StateError('Plugin initialization failed');

        when(
          () => plugin.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse: any(
              named: 'onDidReceiveNotificationResponse',
            ),
          ),
        ).thenThrow(failure);

        await expectLater(service.initialize(), throwsA(same(failure)));

        expect(service.isInitialized, isFalse);
      },
    );
  });

  group('Notification permissions', () {
    setUp(() async {
      await service.initialize();
    });

    test('returns the Android permission result', () async {
      expect(await service.requestPermissions(), isTrue);

      when(() => androidPlugin.requestNotificationsPermission())
          .thenAnswer((_) async => false);

      expect(await service.requestPermissions(), isFalse);
    });

    test('treats an unknown Android permission result as denied', () async {
      when(() => androidPlugin.requestNotificationsPermission())
          .thenAnswer((_) async => null);

      expect(await service.requestPermissions(), isFalse);
    });

    test(
      'returns false when the Android implementation is unavailable',
      () async {
        when(
          () => plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >(),
        ).thenReturn(null);

        expect(await service.requestPermissions(), isFalse);
      },
    );

    test('requests iOS alerts and sound without badge permission', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(await service.requestPermissions(), isTrue);

      verify(
        () => iosPlugin.requestPermissions(
          alert: true,
          badge: false,
          sound: true,
        ),
      ).called(1);

      verifyNever(() => androidPlugin.requestNotificationsPermission());
    });

    test('returns false when iOS permission is denied or unknown', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      when(
        () => iosPlugin.requestPermissions(
          alert: true,
          badge: false,
          sound: true,
        ),
      ).thenAnswer((_) async => false);

      expect(await service.requestPermissions(), isFalse);

      when(
        () => iosPlugin.requestPermissions(
          alert: true,
          badge: false,
          sound: true,
        ),
      ).thenAnswer((_) async => null);

      expect(await service.requestPermissions(), isFalse);
    });

    test(
      'other platforms return true without requesting permissions',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;

        expect(await service.requestPermissions(), isTrue);

        verifyNever(() => androidPlugin.requestNotificationsPermission());

        verifyNever(
          () => iosPlugin.requestPermissions(
            alert: true,
            badge: false,
            sound: true,
          ),
        );
      },
    );
  });

  group('Immediate notifications', () {
    setUp(() async {
      await service.initialize();
    });

    test(
      'forwards notification content and uses the schedule channel',
      () async {
        await service.showNotification(
          id: 42,
          title: 'Class reminder',
          body: 'Class starts soon.',
          payload: 'event:42',
        );

        expect(shown, hasLength(1));
        final call = shown.single;

        expect(call[#id], 42);
        expect(call[#title], 'Class reminder');
        expect(call[#body], 'Class starts soon.');
        expect(call[#payload], 'event:42');

        final details = call[#notificationDetails] as NotificationDetails;

        expect(details.android!.channelId, 'trailblazer_schedule_reminders');
        expect(details.android!.channelName, 'Schedule reminders');
        expect(details.android!.importance, Importance.high);
        expect(details.android!.priority, Priority.high);
        expect(details.android!.playSound, isTrue);
        expect(details.iOS!.presentAlert, isTrue);
        expect(details.iOS!.presentSound, isTrue);
      },
    );

    test(
      'motivation notifications use their separate lower-priority channel',
      () async {
        await service.showNotification(
          id: 7,
          title: 'Keep moving',
          body: 'A little movement goes a long way.',
          isMotivation: true,
        );

        final call = shown.single;
        final details = call[#notificationDetails] as NotificationDetails;

        expect(call[#payload], isNull);
        expect(details.android!.channelId, 'trailblazer_motivation');
        expect(details.android!.channelName, 'Motivation');
        expect(details.android!.importance, Importance.defaultImportance);
        expect(details.android!.priority, Priority.defaultPriority);
        expect(details.android!.playSound, isTrue);
      },
    );
  });

  group('Single event reminders', () {
    setUp(() async {
      await service.initialize();
    });

    test(
      'schedules the default reminder fifteen minutes before an event',
      () async {
        // Use a date well ahead of now to avoid timing-dependent failures.
        final eventStart = DateTime.now().add(const Duration(days: 2));

        final result = await service.scheduleEventReminder(
          notificationId: 100,
          title: 'Team meeting',
          eventStart: eventStart,
          payload: 'event:100',
        );

        expect(result, isTrue);
        expect(scheduled, hasLength(1));

        final call = scheduled.single;
        final scheduledDate = call[#scheduledDate] as tz.TZDateTime;

        expect(call[#id], 100);
        expect(call[#title], 'Team meeting');
        expect(call[#body], 'Your scheduled event is coming up.');
        expect(call[#payload], 'event:100');

        // Compare absolute instants so the test also works outside Chicago.
        expect(
          scheduledDate.toUtc(),
          eventStart.subtract(const Duration(minutes: 15)).toUtc(),
        );

        expect(scheduledDate.location.name, 'America/Chicago');
        expect(
          call[#androidScheduleMode],
          AndroidScheduleMode.inexactAllowWhileIdle,
        );

        final details = call[#notificationDetails] as NotificationDetails;
        expect(details.android!.channelId, 'trailblazer_schedule_reminders');
      },
    );

    test('uses a custom lead time and trims the location', () async {
      final eventStart = DateTime.now().add(const Duration(days: 2));

      await service.scheduleEventReminder(
        notificationId: 101,
        title: 'Workout',
        eventStart: eventStart,
        minutesBefore: 30,
        location: '  Campus gym  ',
      );

      final call = scheduled.single;
      final scheduledDate = call[#scheduledDate] as tz.TZDateTime;

      expect(call[#body], 'Coming up at Campus gym.');
      expect(
        scheduledDate.toUtc(),
        eventStart.subtract(const Duration(minutes: 30)).toUtc(),
      );
    });

    test('blank locations use the generic reminder message', () async {
      await service.scheduleEventReminder(
        notificationId: 102,
        title: 'Study',
        eventStart: DateTime.now().add(const Duration(days: 2)),
        location: '   ',
      );

      expect(scheduled.single[#body], 'Your scheduled event is coming up.');
    });

    test('does not schedule a reminder whose alert time has passed', () async {
      // The event is future, but its fifteen-minute reminder is overdue.
      final result = await service.scheduleEventReminder(
        notificationId: 103,
        title: 'Starting soon',
        eventStart: DateTime.now().add(const Duration(minutes: 5)),
      );

      expect(result, isFalse);
      expect(scheduled, isEmpty);
    });

    test('does not schedule events already in the past', () async {
      final result = await service.scheduleEventReminder(
        notificationId: 104,
        title: 'Old event',
        eventStart: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(result, isFalse);
      expect(scheduled, isEmpty);
    });

    test('zero lead time schedules at the future event start', () async {
      final eventStart = DateTime.now().add(const Duration(days: 2));

      expect(
        await service.scheduleEventReminder(
          notificationId: 105,
          title: 'Event',
          eventStart: eventStart,
          minutesBefore: 0,
        ),
        isTrue,
      );

      final scheduledDate = scheduled.single[#scheduledDate] as tz.TZDateTime;

      expect(scheduledDate.toUtc(), eventStart.toUtc());
    });
  });

  group('Recurring event reminders', () {
    setUp(() async {
      await service.initialize();
    });

    test('clears all reserved IDs and counts only future reminders', () async {
      final now = DateTime.now();

      final count = await service.scheduleEventReminderOccurrences(
        firstNotificationId: 1000,
        title: 'Repeated event',
        eventStartTimes: [
          now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 1)),
          now.add(const Duration(days: 2)),
        ],
        payloadPrefix: 'event:abc',
        location: 'Library',
      );

      // Clear the full range so old repeat reminders cannot remain queued.
      expect(cancelled, List.generate(60, (index) => 1000 + index));
      expect(count, 2);

      // Skipping a past event must not change later occurrence IDs.
      expect(scheduled.map((call) => call[#id]).toList(), [1001, 1002]);
      expect(scheduled.map((call) => call[#payload]).toList(), [
        'event:abc:1',
        'event:abc:2',
      ]);
      expect(
        scheduled.every((call) => call[#body] == 'Coming up at Library.'),
        isTrue,
      );
    });

    test('limits a large occurrence list to the first sixty', () async {
      final base = DateTime.now().add(const Duration(days: 2));

      final count = await service.scheduleEventReminderOccurrences(
        firstNotificationId: 2000,
        title: 'Daily activity',
        eventStartTimes: List.generate(
          65,
          (index) => base.add(Duration(days: index)),
        ),
      );

      expect(count, 60);
      expect(scheduled, hasLength(60));
      expect(scheduled.first[#id], 2000);
      expect(scheduled.last[#id], 2059);
      expect(scheduled.every((call) => call[#payload] == null), isTrue);
    });

    test(
      'an empty list cancels stale reminders without scheduling any',
      () async {
        final count = await service.scheduleEventReminderOccurrences(
          firstNotificationId: 3000,
          title: 'Removed repeats',
          eventStartTimes: [],
        );

        expect(count, 0);
        expect(scheduled, isEmpty);
        expect(cancelled, List.generate(60, (index) => 3000 + index));
      },
    );

    test('all overdue occurrences produce a scheduled count of zero', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      final count = await service.scheduleEventReminderOccurrences(
        firstNotificationId: 4000,
        title: 'Past repeats',
        eventStartTimes: [
          yesterday,
          yesterday.subtract(const Duration(days: 1)),
        ],
      );

      expect(count, 0);
      expect(scheduled, isEmpty);
      expect(cancelled, hasLength(60));
    });
  });

  group('Cancellation and pending reminders', () {
    setUp(() async {
      await service.initialize();
    });

    test('cancels only the requested notification ID', () async {
      await service.cancelNotification(55);

      expect(cancelled, [55]);
    });

    test('cancels the complete sixty-ID occurrence range', () async {
      await service.cancelEventReminderOccurrences(5000);

      expect(cancelled, List.generate(60, (index) => 5000 + index));
    });

    test('forwards cancel-all to the plugin', () async {
      await service.cancelAllNotifications();

      verify(() => plugin.cancelAll()).called(1);
      expect(cancelled, isEmpty);
    });

    test('returns pending notification content from the plugin', () async {
      final pending = [
        PendingNotificationRequest(1, 'Class', 'Starts soon', 'event:1'),
        PendingNotificationRequest(2, 'Workout', 'Gym time', 'event:2'),
      ];

      when(() => plugin.pendingNotificationRequests())
          .thenAnswer((_) async => pending);

      final result = await service.getPendingNotifications();

      expect(result, same(pending));
      expect(result.map((item) => item.id).toList(), [1, 2]);
      expect(result.first.payload, 'event:1');
    });

    test('returns an empty list when no reminders are pending', () async {
      expect(await service.getPendingNotifications(), isEmpty);
    });

    test('propagates native cancellation errors to the caller', () async {
      final failure = StateError('Native cancellation failed');

      when(() => plugin.cancelAll()).thenThrow(failure);

      await expectLater(
        service.cancelAllNotifications(),
        throwsA(same(failure)),
      );
    });
  });
}
