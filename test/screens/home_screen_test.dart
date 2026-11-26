// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:test_ap_1/screens/home_screen.dart';
import 'package:test_ap_1/services/app_settings.dart';
import 'package:test_ap_1/services/schedule_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platformVariant = TargetPlatformVariant({TargetPlatform.windows});

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  String dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  DateTime tomorrow() {
    return DateTime.now().add(const Duration(days: 1));
  }

  Map<String, dynamic> createEvent({
    required String name,
    DateTime? date,
    String startTime = '09:00',
    String endTime = '10:00',
    String location = 'Room 101',
    bool allDay = false,
  }) {
    return {
      'id': name,
      'name': name,
      'date': dateKey(date ?? tomorrow()),
      'startTime': startTime,
      'endTime': endTime,
      'location': location,
      'repeatWeekly': false,
      'repeatYearly': false,
      'allDay': allDay,
    };
  }

  Map<String, dynamic> createTodo({
    required String name,
    int importance = 3,
    bool completed = false,
    DateTime? date,
  }) {
    return {
      'id': name,
      'entryType': 'todo',
      'name': name,
      'date': dateKey(date ?? DateTime.now()),
      'importance': importance,
      'completed': completed,
    };
  }

  Future<void> loadScreen(
    WidgetTester tester, {
    List<Map<String, dynamic>> entries = const [],
    VoidCallback? onOpenSchedule,
  }) async {
    SharedPreferences.setMockInitialValues({
      'trailblazer-schedule': jsonEncode(entries),
    });

    await tester.binding.setSurfaceSize(const Size(800, 2000));

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HomeScreen(onOpenSchedule: onOpenSchedule)),
      ),
    );

    await tester.pumpAndSettle();
  }

  Future<void> tapWidget(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // Test 1: Home screen rendering
  testWidgets('displays home dashboard', (tester) async {
    await loadScreen(tester);

    expect(find.byType(HomeScreen), findsOneWidget);

    expect(find.text('Your day at a glance'), findsOneWidget);

    expect(find.text('Coming up'), findsOneWidget);

    expect(find.text('Wellness at a glance'), findsOneWidget);

    expect(find.byTooltip('Refresh dashboard'), findsOneWidget);

    expect(find.byType(RefreshIndicator), findsOneWidget);
  }, variant: platformVariant);

  // Test 2: Time-based greeting
  testWidgets('displays appropriate time-based greeting', (tester) async {
    final hour = DateTime.now().hour;

    await loadScreen(tester);

    final expectedGreeting = hour < 12
        ? 'GOOD MORNING'
        : hour < 17
        ? 'GOOD AFTERNOON'
        : 'GOOD EVENING';

    expect(find.text(expectedGreeting), findsOneWidget);
  }, variant: platformVariant);

  // Test 3: Current date
  testWidgets('displays current weekday and date', (tester) async {
    await loadScreen(tester);

    final now = DateTime.now();

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final expectedDate =
        '${weekdays[now.weekday - 1]}, '
        '${months[now.month - 1]} ${now.day}';

    expect(find.text(expectedDate), findsOneWidget);
  }, variant: platformVariant);

  // Test 4: Empty schedule
  testWidgets('displays empty upcoming schedule message', (tester) async {
    await loadScreen(tester);

    expect(
      find.text(
        'Nothing coming up on your schedule. '
        'Enjoy the open time!',
      ),
      findsOneWidget,
    );

    expect(find.byTooltip('Next event'), findsNothing);

    expect(find.byTooltip('Previous event'), findsNothing);
  }, variant: platformVariant);

  // Test 5: Wellness statistics
  testWidgets('displays wellness statistic categories', (tester) async {
    await loadScreen(tester);

    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);

    expect(find.byIcon(Icons.directions_walk_rounded), findsOneWidget);

    expect(find.byIcon(Icons.water_drop_outlined), findsOneWidget);

    expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
  }, variant: platformVariant);

  // Test 6: Health Connect unavailable
  testWidgets('displays Health Connect fallback message', (tester) async {
    await loadScreen(tester);

    expect(find.text('Connect in Fitness'), findsOneWidget);
  }, variant: platformVariant);

  // Test 7: Default water intake
  testWidgets('displays default water intake in selected units', (
    tester,
  ) async {
    await loadScreen(tester);

    final expectedWater = AppSettings.instance.isMetric ? '0 ml' : '0 fl oz';

    expect(find.text(expectedWater), findsOneWidget);
  }, variant: platformVariant);

  // Test 8: Default sleep information
  testWidgets('displays placeholder when sleep data is unavailable', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.text('Sleep'), findsOneWidget);

    expect(find.text('—'), findsOneWidget);
  }, variant: platformVariant);

  // Test 9: Signed-out workout status
  testWidgets('displays fitness sign-in requirement', (tester) async {
    await loadScreen(tester);

    expect(find.text('Fitness schedule unavailable'), findsOneWidget);

    expect(
      find.text('Sign in to view your weekly training plan.'),
      findsOneWidget,
    );
  }, variant: platformVariant);

  // Test 10: Weekly workout summary
  testWidgets('displays default weekly fitness summary', (tester) async {
    await loadScreen(tester);

    expect(find.text('This week in fitness'), findsOneWidget);

    expect(find.text('0 completed workouts · 0 min total'), findsOneWidget);
  }, variant: platformVariant);

  // Test 11: Motivational message
  testWidgets('displays dashboard motivational message', (tester) async {
    await loadScreen(tester);

    expect(
      find.text('Move well. Study well. Play well. Rest well.'),
      findsOneWidget,
    );
  }, variant: platformVariant);

  // Test 12: Upcoming event rendering
  testWidgets('displays upcoming schedule event', (tester) async {
    await loadScreen(
      tester,
      entries: [createEvent(name: 'Cybersecurity Class', location: 'Room 101')],
    );

    expect(find.text('Cybersecurity Class'), findsOneWidget);

    expect(find.textContaining('Room 101'), findsOneWidget);

    expect(find.textContaining('Tomorrow'), findsOneWidget);

    expect(find.text('1 of 1'), findsOneWidget);

    expect(find.text('View full Schedule'), findsOneWidget);
  }, variant: platformVariant);

  // Test 13: Upcoming event sorting
  testWidgets('sorts upcoming events chronologically', (tester) async {
    await loadScreen(
      tester,
      entries: [
        createEvent(
          name: 'Afternoon Class',
          startTime: '14:00',
          endTime: '15:00',
        ),
        createEvent(
          name: 'Morning Class',
          startTime: '09:00',
          endTime: '10:00',
        ),
      ],
    );

    expect(find.text('Morning Class'), findsOneWidget);

    expect(find.text('Afternoon Class'), findsNothing);

    expect(find.text('1 of 2'), findsOneWidget);
  }, variant: platformVariant);

  // Test 14: Event carousel navigation
  testWidgets('navigates between upcoming events', (tester) async {
    await loadScreen(
      tester,
      entries: [
        createEvent(name: 'First Class', startTime: '09:00', endTime: '10:00'),
        createEvent(name: 'Second Class', startTime: '11:00', endTime: '12:00'),
      ],
    );

    expect(find.text('First Class'), findsOneWidget);

    await tapWidget(tester, find.byTooltip('Next event'));

    expect(find.text('Second Class'), findsOneWidget);

    expect(find.text('2 of 2'), findsOneWidget);

    expect(find.byTooltip('Next event'), findsNothing);

    await tapWidget(tester, find.byTooltip('Previous event'));

    expect(find.text('First Class'), findsOneWidget);

    expect(find.text('1 of 2'), findsOneWidget);

    expect(find.byTooltip('Previous event'), findsNothing);
  }, variant: platformVariant);

  // Test 15: Upcoming event display limit
  testWidgets('limits upcoming events to three entries', (tester) async {
    await loadScreen(
      tester,
      entries: [
        createEvent(name: 'Event One', startTime: '08:00', endTime: '09:00'),
        createEvent(name: 'Event Two', startTime: '10:00', endTime: '11:00'),
        createEvent(name: 'Event Three', startTime: '12:00', endTime: '13:00'),
        createEvent(name: 'Event Four', startTime: '14:00', endTime: '15:00'),
      ],
    );

    expect(find.text('1 of 3'), findsOneWidget);

    await tapWidget(tester, find.byTooltip('Next event'));

    await tapWidget(tester, find.byTooltip('Next event'));

    expect(find.text('Event Three'), findsOneWidget);

    expect(find.text('3 of 3'), findsOneWidget);

    expect(find.byTooltip('Next event'), findsNothing);

    expect(find.text('Event Four'), findsNothing);
  }, variant: platformVariant);

  // Test 16: Exclude expired and invalid events
  testWidgets('excludes expired events and invalid event times', (
    tester,
  ) async {
    await loadScreen(
      tester,
      entries: [
        createEvent(
          name: 'Expired Class',
          date: DateTime.now().subtract(const Duration(days: 1)),
        ),
        createEvent(name: 'Invalid Class', startTime: '25:00'),
        createEvent(name: 'Valid Class'),
      ],
    );

    expect(find.text('Valid Class'), findsOneWidget);

    expect(find.text('Expired Class'), findsNothing);

    expect(find.text('Invalid Class'), findsNothing);

    expect(find.text('1 of 1'), findsOneWidget);
  }, variant: platformVariant);

  // Test 17: Full schedule navigation callback
  testWidgets('invokes callback when viewing full schedule', (tester) async {
    int callbackCount = 0;

    await loadScreen(
      tester,
      entries: [createEvent(name: 'Networking Class')],
      onOpenSchedule: () {
        callbackCount++;
      },
    );

    expect(callbackCount, 0);

    await tapWidget(tester, find.text('View full Schedule'));

    expect(callbackCount, 1);
  }, variant: platformVariant);

  // Test 18: To-do filtering and priority
  testWidgets('displays two highest-priority incomplete tasks', (tester) async {
    await loadScreen(
      tester,
      entries: [
        createTodo(name: 'Low Priority Task', importance: 1),
        createTodo(name: 'High Priority Task', importance: 5),
        createTodo(name: 'Medium Priority Task', importance: 3),
        createTodo(name: 'Completed Task', importance: 5, completed: true),
        createTodo(name: 'Tomorrow Task', importance: 5, date: tomorrow()),
      ],
    );

    expect(find.text('Today’s to-do'), findsOneWidget);

    expect(find.text('High Priority Task'), findsOneWidget);

    expect(find.text('Medium Priority Task'), findsOneWidget);

    expect(find.text('Low Priority Task'), findsNothing);

    expect(find.text('Completed Task'), findsNothing);

    expect(find.text('Tomorrow Task'), findsNothing);

    expect(find.byType(CheckboxListTile), findsNWidgets(2));

    final taskTiles = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();

    expect((taskTiles.first.title as Text).data, 'High Priority Task');

    expect((taskTiles.last.title as Text).data, 'Medium Priority Task');

    expect(find.text('Importance 5 / 5'), findsOneWidget);
  }, variant: platformVariant);

  // Test 19: Complete and persist a to-do task
  testWidgets('marks task as completed and saves updated state', (
    tester,
  ) async {
    await loadScreen(
      tester,
      entries: [createTodo(name: 'Complete Assignment', importance: 5)],
    );

    final task = find.widgetWithText(CheckboxListTile, 'Complete Assignment');

    expect(task, findsOneWidget);

    expect(tester.widget<CheckboxListTile>(task).value, isFalse);

    await tapWidget(tester, task);

    expect(find.text('Complete Assignment'), findsNothing);

    expect(find.text('Today’s to-do'), findsNothing);

    final savedEntries = await ScheduleService.loadEntries();

    expect(savedEntries.length, 1);

    expect(savedEntries.first['name'], 'Complete Assignment');

    expect(savedEntries.first['completed'], isTrue);
  }, variant: platformVariant);

  // Test 20: Dashboard refresh
  testWidgets('refreshes dashboard after schedule changes', (tester) async {
    await loadScreen(tester);

    expect(
      find.text(
        'Nothing coming up on your schedule. '
        'Enjoy the open time!',
      ),
      findsOneWidget,
    );

    await ScheduleService.saveEntries([
      createEvent(name: 'New Study Session', location: 'University Library'),
    ]);

    await tapWidget(tester, find.byTooltip('Refresh dashboard'));

    expect(find.text('New Study Session'), findsOneWidget);

    expect(find.textContaining('University Library'), findsOneWidget);

    expect(
      find.text(
        'Nothing coming up on your schedule. '
        'Enjoy the open time!',
      ),
      findsNothing,
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);

    expect(tester.takeException(), isNull);
  }, variant: platformVariant);
}
