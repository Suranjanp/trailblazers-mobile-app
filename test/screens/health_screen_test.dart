// ignore_for_file: depend_on_referenced_packages

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:test_ap_1/screens/health_screen.dart';

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

  const signInMessage = 'Please sign in to save and view your health history.';

  Future<void> loadScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HealthScreen())),
    );

    await tester.pumpAndSettle();
  }

  Future<void> tapWidget(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // Test 1: Health screen rendering
  testWidgets('renders health screen successfully', (tester) async {
    await loadScreen(tester);

    expect(find.byType(HealthScreen), findsOneWidget);

    expect(find.text(signInMessage), findsOneWidget);

    expect(tester.takeException(), isNull);
  }, variant: platformVariant);

  // Test 2: Authentication requirement
  testWidgets('displays sign-in requirement to signed-out users', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.text(signInMessage), findsOneWidget);

    expect(find.text('Your Health'), findsNothing);
  }, variant: platformVariant);

  // Test 3: Error state icon
  testWidgets('displays unavailable health data icon', (tester) async {
    await loadScreen(tester);

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

    expect(find.text(signInMessage), findsOneWidget);
  }, variant: platformVariant);

  // Test 4: Retry button rendering
  testWidgets('displays an enabled retry button', (tester) async {
    await loadScreen(tester);

    final retryButton = find.widgetWithText(ElevatedButton, 'Try again');

    expect(retryButton, findsOneWidget);

    expect(tester.widget<ElevatedButton>(retryButton).onPressed, isNotNull);
  }, variant: platformVariant);

  // Test 5: Retry functionality
  testWidgets('maintains sign-in requirement after retry', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, find.widgetWithText(ElevatedButton, 'Try again'));

    expect(find.text(signInMessage), findsOneWidget);

    expect(find.text('Try again'), findsOneWidget);

    expect(tester.takeException(), isNull);
  }, variant: platformVariant);

  // Test 6: Repeated retry functionality
  testWidgets('handles repeated retry attempts without crashing', (
    tester,
  ) async {
    await loadScreen(tester);

    final retryButton = find.widgetWithText(ElevatedButton, 'Try again');

    for (int i = 0; i < 3; i++) {
      await tapWidget(tester, retryButton);

      expect(find.text(signInMessage), findsOneWidget);

      expect(retryButton, findsOneWidget);
    }

    expect(tester.takeException(), isNull);
  }, variant: platformVariant);

  // Test 7: Daily overview restriction
  testWidgets('hides daily health overview when signed out', (tester) async {
    await loadScreen(tester);

    expect(find.text('Daily Overview'), findsNothing);

    expect(find.text('Water'), findsNothing);
    expect(find.text('Sleep'), findsNothing);
    expect(find.text('Your Health'), findsNothing);
  }, variant: platformVariant);

  // Test 8: Water tracking restriction
  testWidgets('hides water intake tracking when signed out', (tester) async {
    await loadScreen(tester);

    expect(find.text('Water Intake'), findsNothing);

    expect(find.text('Your Daily Hydration'), findsNothing);

    expect(find.text('Add a cup'), findsNothing);

    expect(find.byIcon(Icons.water_drop), findsNothing);
  }, variant: platformVariant);

  // Test 9: Water increment restriction
  testWidgets('hides metric and imperial water increment controls', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.text('+250 ml'), findsNothing);

    expect(find.text('+8 fl oz'), findsNothing);

    expect(find.text('Add a cup'), findsNothing);
  }, variant: platformVariant);

  // Test 10: Hydration goal restriction
  testWidgets('hides daily hydration goals when signed out', (tester) async {
    await loadScreen(tester);

    expect(find.textContaining('daily goal'), findsNothing);

    expect(find.textContaining('remaining'), findsNothing);

    expect(find.text('Daily water goal reached!'), findsNothing);
  }, variant: platformVariant);

  // Test 11: Reset water restriction
  testWidgets('hides reset water intake control', (tester) async {
    await loadScreen(tester);

    expect(find.text('Reset water intake'), findsNothing);

    expect(find.byIcon(Icons.refresh), findsNothing);

    expect(find.byType(TextButton), findsNothing);
  }, variant: platformVariant);

  // Test 12: Sleep tracking restriction
  testWidgets('hides sleep tracking when signed out', (tester) async {
    await loadScreen(tester);

    expect(find.text('Sleep Tracking'), findsNothing);

    expect(find.text("Last Night's Sleep"), findsNothing);

    expect(find.text('Daily goal: 8 hours'), findsNothing);

    expect(find.byIcon(Icons.bedtime), findsNothing);
  }, variant: platformVariant);

  // Test 13: Sleep logging restriction
  testWidgets('hides sleep logging and editing controls', (tester) async {
    await loadScreen(tester);

    expect(find.text('Log Sleep Hours'), findsNothing);

    expect(find.text('Edit Sleep Hours'), findsNothing);

    expect(find.byIcon(Icons.edit), findsNothing);
  }, variant: platformVariant);

  // Test 14: Sleep entry dialog restriction
  testWidgets('does not display sleep entry form when signed out', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.byType(AlertDialog), findsNothing);

    expect(find.byType(TextFormField), findsNothing);

    expect(find.text('Log Sleep'), findsNothing);

    expect(find.text('Hours slept'), findsNothing);

    expect(find.text('Save'), findsNothing);
  }, variant: platformVariant);

  // Test 15: Weekly health progress restriction
  testWidgets('hides weekly health progress when signed out', (tester) async {
    await loadScreen(tester);

    expect(find.text('Weekly Progress'), findsNothing);

    expect(find.text('Avg. water'), findsNothing);

    expect(find.text('Avg. sleep'), findsNothing);

    expect(find.textContaining('days logged'), findsNothing);

    expect(find.textContaining('nights logged'), findsNothing);
  }, variant: platformVariant);

  // Test 16: Weekly navigation restriction
  testWidgets('hides previous and next week navigation', (tester) async {
    await loadScreen(tester);

    expect(find.byTooltip('Previous week'), findsNothing);

    expect(find.byTooltip('Next week'), findsNothing);

    expect(find.byIcon(Icons.chevron_left), findsNothing);

    expect(find.byIcon(Icons.chevron_right), findsNothing);
  }, variant: platformVariant);

  // Test 17: Loading indicator verification
  testWidgets('does not display loading indicators when signed out', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);

    expect(find.byType(LinearProgressIndicator), findsNothing);

    expect(find.text(signInMessage), findsOneWidget);
  }, variant: platformVariant);

  // Test 18: Correct error message
  testWidgets('displays authentication error instead of network error', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.text(signInMessage), findsOneWidget);

    expect(
      find.text(
        'Unable to load your health history. '
        'Check your connection and try again.',
      ),
      findsNothing,
    );

    expect(
      find.text('Unable to load that week. Please try again.'),
      findsNothing,
    );
  }, variant: platformVariant);

  // Test 19: Available action verification
  testWidgets('only displays retry action when signed out', (tester) async {
    await loadScreen(tester);

    expect(find.byType(ElevatedButton), findsOneWidget);

    expect(find.widgetWithText(ElevatedButton, 'Try again'), findsOneWidget);

    expect(find.byType(FilledButton), findsNothing);

    expect(find.byType(IconButton), findsNothing);

    expect(find.byType(SingleChildScrollView), findsNothing);
  }, variant: platformVariant);

  // Test 20: Screen lifecycle and stability
  testWidgets('maintains signed-out state after screen recreation', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.text(signInMessage), findsOneWidget);

    // Remove HealthScreen to test disposal.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    await tester.pumpAndSettle();

    expect(find.byType(HealthScreen), findsNothing);

    // Recreate HealthScreen.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HealthScreen())),
    );

    await tester.pumpAndSettle();

    expect(find.byType(HealthScreen), findsOneWidget);

    expect(find.text(signInMessage), findsOneWidget);

    expect(find.text('Try again'), findsOneWidget);

    expect(tester.takeException(), isNull);
  }, variant: platformVariant);
}
