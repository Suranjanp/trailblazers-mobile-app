import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_ap_1/screens/schedule_screen.dart';
import 'package:test_ap_1/services/schedule_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> loadScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ScheduleScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> tapWidget(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // Test 1: Schedule screen rendering
  testWidgets('displays schedule screen', (tester) async {
    await loadScreen(tester);

    expect(find.text('My Schedule'), findsOneWidget);
    expect(
      find.text('Manage your classes, activities, and tasks.'),
      findsOneWidget,
    );
    expect(find.text('Add event'), findsOneWidget);
    expect(find.text('Connect Google Calendar'), findsOneWidget);
  });

  // Test 2: Empty schedule
  testWidgets('displays empty schedule message', (tester) async {
    await loadScreen(tester);

    expect(
      find.text('No classes or events scheduled for this day.'),
      findsOneWidget,
    );
    expect(find.text('0 entries'), findsOneWidget);
  });

  // Test 3: Weekday rendering
  testWidgets('displays all seven weekdays', (tester) async {
    await loadScreen(tester);

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    for (final day in weekdays) {
      expect(find.text(day), findsOneWidget);
    }
  });

  // Test 4: Day selection
  testWidgets('allows users to select a weekday', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, find.text('Mon'));

    expect(find.text("Mon's activities"), findsOneWidget);

    await tapWidget(tester, find.text('Fri'));

    expect(find.text("Fri's activities"), findsOneWidget);
  });

  // Test 5: Week navigation
  testWidgets('navigates to next and previous week', (tester) async {
    await loadScreen(tester);

    final weekLabel = find.textContaining(' – ');

    final originalWeek = tester.widget<Text>(weekLabel).data;

    await tapWidget(tester, find.byTooltip('Next week'));

    final nextWeek = tester.widget<Text>(weekLabel).data;

    expect(nextWeek, isNot(originalWeek));

    await tapWidget(tester, find.byTooltip('Previous week'));

    expect(tester.widget<Text>(weekLabel).data, originalWeek);
  });

  // Test 6: Monthly calendar view
  testWidgets('switches between weekly and monthly views', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, find.text('Tap to view month'));

    expect(find.byType(GridView), findsOneWidget);

    await tapWidget(tester, find.text('Tap to view month'));

    expect(find.byType(GridView), findsNothing);
  });

  // Test 7: Add event dialog
  testWidgets('opens add event dialog', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, find.text('Add event'));

    expect(find.text('Add class or activity'), findsOneWidget);
    expect(find.text('Class or activity'), findsOneWidget);
    expect(find.text('Location (optional)'), findsOneWidget);
    expect(find.text('Save entry'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  // Test 8: Empty event name validation
  testWidgets('rejects event with empty name', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, find.text('Add event'));
    await tapWidget(tester, find.text('Save entry'));

    expect(find.text('Enter a name for this event.'), findsOneWidget);

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  // Test 9: Cancel event creation
  testWidgets('cancels event creation', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, find.text('Add event'));
    await tapWidget(tester, find.text('Cancel'));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('0 entries'), findsOneWidget);
  });

  // Test 10: Create and save event
  testWidgets('creates and saves a schedule event', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, find.text('Add event'));

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Cybersecurity Class',
    );

    await tester.enterText(find.byType(TextFormField).at(1), 'Room 101');

    await tapWidget(tester, find.text('Save entry'));

    expect(find.text('Cybersecurity Class'), findsOneWidget);
    expect(find.textContaining('Room 101'), findsOneWidget);
    expect(find.text('1 entry'), findsOneWidget);

    final entries = await ScheduleService.loadEntries();

    expect(entries.length, 1);
    expect(entries.first['name'], 'Cybersecurity Class');
    expect(entries.first['location'], 'Room 101');
    expect(entries.first['duration'], 60);
    expect(entries.first['repeatWeekly'], isTrue);
  });

  // Test 11: Recurrence selection
  testWidgets('weekly and yearly recurrence are mutually exclusive', (
    tester,
  ) async {
    await loadScreen(tester);

    await tapWidget(tester, find.text('Add event'));

    final weekly = find.widgetWithText(SwitchListTile, 'Repeat weekly');

    final yearly = find.widgetWithText(SwitchListTile, 'Repeat yearly');

    expect(tester.widget<SwitchListTile>(weekly).value, isTrue);

    expect(tester.widget<SwitchListTile>(yearly).value, isFalse);

    await tapWidget(tester, yearly);

    expect(tester.widget<SwitchListTile>(weekly).value, isFalse);

    expect(tester.widget<SwitchListTile>(yearly).value, isTrue);
  });

  // Test 12: Empty to-do list
  testWidgets('displays empty to-do list', (tester) async {
    await loadScreen(tester);

    await tester.scrollUntilVisible(find.text('To-do list'), 150);

    expect(find.text('To-do list'), findsOneWidget);
    expect(find.text('0/0 done'), findsOneWidget);

    expect(
      find.text('No tasks for this day. Add one when you need it.'),
      findsOneWidget,
    );
  });

  // Test 13: Add task dialog
  testWidgets('opens add task dialog', (tester) async {
    await loadScreen(tester);

    await tester.scrollUntilVisible(find.byTooltip('Add task'), 150);

    await tapWidget(tester, find.byTooltip('Add task'));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Task'), findsOneWidget);
    expect(find.text('Importance'), findsOneWidget);
    expect(find.text('3 / 5'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  // Test 14: Empty task validation
  testWidgets('rejects task with empty title', (tester) async {
    await loadScreen(tester);

    await tester.scrollUntilVisible(find.byTooltip('Add task'), 150);

    await tapWidget(tester, find.byTooltip('Add task'));

    await tapWidget(tester, find.widgetWithText(FilledButton, 'Add task'));

    expect(find.byType(AlertDialog), findsOneWidget);

    final entries = await ScheduleService.loadEntries();
    expect(entries, isEmpty);
  });

  // Test 15: Create and save task
  testWidgets('creates and saves a to-do task', (tester) async {
    await loadScreen(tester);

    await tester.scrollUntilVisible(find.byTooltip('Add task'), 150);

    await tapWidget(tester, find.byTooltip('Add task'));

    await tester.enterText(find.byType(TextFormField), 'Complete assignment');

    await tapWidget(tester, find.widgetWithText(FilledButton, 'Add task'));

    await tester.scrollUntilVisible(find.text('Complete assignment'), 100);

    expect(find.text('Complete assignment'), findsOneWidget);
    expect(find.text('Importance: 3 / 5'), findsOneWidget);
    expect(find.text('0/1 done'), findsOneWidget);

    final entries = await ScheduleService.loadEntries();

    expect(entries.length, 1);
    expect(entries.first['entryType'], 'todo');
    expect(entries.first['name'], 'Complete assignment');
    expect(entries.first['completed'], isFalse);
    expect(entries.first['importance'], 3);
  });
}
