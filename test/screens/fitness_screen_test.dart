// ignore_for_file: depend_on_referenced_packages

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:test_ap_1/screens/fitness_screen.dart';
import 'package:test_ap_1/services/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platformVariant = TargetPlatformVariant({TargetPlatform.windows});

  const signInMessage = 'Please sign in to use fitness tracking.';

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> loadScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FitnessScreen())),
    );

    await tester.pumpAndSettle();
  }

  void expectHidden(List<String> labels) {
    for (final label in labels) {
      expect(
        find.text(label),
        findsNothing,
        reason: '$label should not be visible.',
      );
    }
  }

  // Test 1: Screen initialization
  testWidgets('initializes FitnessScreen successfully', (tester) async {
    await loadScreen(tester);

    expect(find.byType(FitnessScreen), findsOneWidget);

    expect(tester.takeException(), isNull);
  }, variant: platformVariant);

  // Test 2: Authentication requirement
  testWidgets('displays sign-in message for unauthenticated users', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.text(signInMessage), findsOneWidget);

    expect(
      find.ancestor(
        of: find.text(signInMessage),
        matching: find.byType(Center),
      ),
      findsOneWidget,
    );
  }, variant: platformVariant);

  // Test 3: Fitness dashboard visibility
  testWidgets('hides personalized fitness dashboard', (tester) async {
    await loadScreen(tester);

    expectHidden(['YOUR ACTIVITY', 'Fitness']);

    expect(find.byType(SingleChildScrollView), findsNothing);
  }, variant: platformVariant);

  // Test 4: Workout starting controls
  testWidgets('hides workout starting controls', (tester) async {
    await loadScreen(tester);

    expectHidden([
      'Ready to move?',
      'Start a workout',
      'Starting...',
      'Start a workout and track your time, distance, and notes.',
    ]);

    expect(find.byType(FilledButton), findsNothing);

    expect(find.byIcon(Icons.play_arrow), findsNothing);
  }, variant: platformVariant);

  // Test 5: Workout selection
  testWidgets('hides workout selection options', (tester) async {
    await loadScreen(tester);

    expectHidden([
      'Choose a workout',
      'Other workouts',
      'Walking',
      'Running',
      'Cycling',
      'Strength training',
      'Swimming',
      'Yoga',
      'Hiking',
      'HIIT',
      'Other',
    ]);

    expect(find.byType(BottomSheet), findsNothing);
  }, variant: platformVariant);

  // Test 6: Health Connect controls
  testWidgets('hides Health Connect integration controls', (tester) async {
    await loadScreen(tester);

    expectHidden([
      'Daily health data',
      'Connect Health Connect',
      'Refresh health data',
      'Install or update Health Connect',
      'Checking availability...',
      'Connecting...',
      'Refreshing...',
    ]);

    expect(find.byType(OutlinedButton), findsNothing);
  }, variant: platformVariant);

  // Test 7: Health metrics
  testWidgets('hides daily health metrics and step progress', (tester) async {
    await loadScreen(tester);

    expectHidden(['Steps today', 'Walking distance']);

    expect(find.textContaining('10,000-step reference goal'), findsNothing);

    expect(find.byType(LinearProgressIndicator), findsNothing);
  }, variant: platformVariant);

  // Test 8: GPS activity tracking
  testWidgets('hides GPS activity tracking features', (tester) async {
    await loadScreen(tester);

    expectHidden([
      'GPS activity tracking',
      'GPS activities',
      'LIVE GPS',
      'Walk',
      'Run',
      'Cycle',
      'GPS tracking active',
      'GPS paused',
      'Preparing GPS activity…',
      'Waiting for GPS location…',
    ]);

    expect(find.byIcon(Icons.gps_fixed), findsNothing);
  }, variant: platformVariant);

  // Test 9: Training and history tabs
  testWidgets('hides training and history navigation', (tester) async {
    await loadScreen(tester);

    expectHidden(['Train', 'History']);

    expect(find.byType(SegmentedButton<String>), findsNothing);
  }, variant: platformVariant);

  // Test 10: Personal training
  testWidgets('hides personal training and training programs', (tester) async {
    await loadScreen(tester);

    expectHidden([
      'Personal training',
      'Goals and coaching preferences',
      'Training programs',
      'Structured plans and progression',
    ]);
  }, variant: platformVariant);

  // Test 11: Exercise library
  testWidgets('hides exercise library and custom workouts', (tester) async {
    await loadScreen(tester);

    expectHidden([
      'Exercise library',
      'Browse and add exercises',
      'Custom workouts',
      'Your saved routines',
    ]);

    expect(find.byType(ExpansionTile), findsNothing);
  }, variant: platformVariant);

  // Test 12: Workout history
  testWidgets('hides workout history and daily summaries', (tester) async {
    await loadScreen(tester);

    expectHidden([
      'Workout history',
      "Today's workouts",
      'Sessions',
      'Time',
      'Distance',
      'No completed workouts yet',
      'Completed workouts will appear here.',
      'Trainer',
    ]);
  }, variant: platformVariant);

  // Test 13: Performance statistics
  testWidgets('hides performance statistics and personal records', (
    tester,
  ) async {
    await loadScreen(tester);

    expectHidden([
      'GPS routes',
      'GPS goals & stats',
      'Training insights',
      'Personal records',
      'Performance trends',
      'Recorded routes and activity details',
      'Weekly distance and activity targets',
      'Best lifts and exercise milestones',
    ]);
  }, variant: platformVariant);

  // Test 14: Active workout controls
  testWidgets('does not display active workout controls', (tester) async {
    await loadScreen(tester);

    expect(find.textContaining('in progress'), findsNothing);

    expectHidden([
      'Finish workout',
      'Save workout',
      'Keep working out',
      'Distance (optional)',
      'Calories (optional)',
      'Notes (optional)',
    ]);

    expect(find.byType(AlertDialog), findsNothing);

    expect(find.byType(TextField), findsNothing);
  }, variant: platformVariant);

  // Test 15: Loading and error states
  testWidgets('displays authentication message without loading errors', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.text(signInMessage), findsOneWidget);

    expect(find.byType(CircularProgressIndicator), findsNothing);

    expect(find.byType(LinearProgressIndicator), findsNothing);

    expectHidden([
      'Could not load your workout. Check your connection and retry.',
      'Could not load workout history. Check your Firestore rules and connection.',
      'Sign in to save and view workouts.',
    ]);

    expect(find.byType(SnackBar), findsNothing);

    expect(tester.takeException(), isNull);
  }, variant: platformVariant);

  // Test 16: Measurement system changes
  testWidgets('remains stable when measurement units change', (tester) async {
    await loadScreen(tester);

    final settings = AppSettings.instance;
    final original = settings.measurementSystem;

    try {
      await Future.sync(
        () => settings.setMeasurementSystem(MeasurementSystem.metric),
      );

      await tester.pumpAndSettle();

      expect(settings.isMetric, isTrue);

      expect(find.text(signInMessage), findsOneWidget);

      await Future.sync(
        () => settings.setMeasurementSystem(MeasurementSystem.imperial),
      );

      await tester.pumpAndSettle();

      expect(settings.isMetric, isFalse);

      expect(find.text(signInMessage), findsOneWidget);

      expect(tester.takeException(), isNull);
    } finally {
      await Future.sync(() => settings.setMeasurementSystem(original));

      await tester.pumpAndSettle();
    }
  }, variant: platformVariant);

  // Test 17: Screen disposal
  testWidgets('disposes FitnessScreen without exceptions', (tester) async {
    await loadScreen(tester);

    final state = tester.state(find.byType(FitnessScreen));

    expect(state.mounted, isTrue);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    await tester.pumpAndSettle();

    expect(state.mounted, isFalse);

    expect(find.byType(FitnessScreen), findsNothing);

    expect(tester.takeException(), isNull);
  }, variant: platformVariant);

  // Test 18: Screen recreation
  testWidgets('recreates FitnessScreen successfully after disposal', (
    tester,
  ) async {
    await loadScreen(tester);

    final originalState = tester.state(find.byType(FitnessScreen));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    await tester.pumpAndSettle();

    expect(originalState.mounted, isFalse);

    await loadScreen(tester);

    final newState = tester.state(find.byType(FitnessScreen));

    expect(newState.mounted, isTrue);

    expect(newState, isNot(same(originalState)));

    expect(find.text(signInMessage), findsOneWidget);

    expect(tester.takeException(), isNull);
  }, variant: platformVariant);
}
