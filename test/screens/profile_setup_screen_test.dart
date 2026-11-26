import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_ap_1/screens/profile_setup_screen.dart';
import 'package:test_ap_1/services/app_settings.dart';

void main() {
  Future<void> loadScreen(
    WidgetTester tester, {
    String initialName = 'Test User',
    Map<String, dynamic> savedProfile = const {},
    bool openedFromProfile = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSetupScreen(
          userId: 'test-user-001',
          initialName: initialName,
          savedProfile: savedProfile,
          openedFromProfile: openedFromProfile,
        ),
        routes: {
          '/home': (_) =>
              const Scaffold(body: Center(child: Text('Home Screen'))),
        },
      ),
    );

    await tester.pumpAndSettle();
  }

  Finder field(String label) {
    return find.widgetWithText(TextFormField, label);
  }

  Future<void> tapWidget(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterField(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    final finder = field(label);

    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pumpAndSettle();
  }

  Future<void> validateForm(WidgetTester tester) async {
    await tapWidget(tester, find.text('Save profile'));
  }

  const validProfile = <String, dynamic>{
    'name': 'Test User',
    'ageYears': 25,
    'heightCm': 175,
    'weightKg': 75,
    'bodyGoal': 'maintain',
    'calorieEquation': 'male',
    'activityLevel': 'inactive',
  };

  // Test 1: Profile setup screen rendering
  testWidgets('displays profile setup screen', (tester) async {
    await loadScreen(tester);

    expect(find.text('Set up your profile'), findsOneWidget);

    expect(find.text('Body & goal'), findsOneWidget);
    expect(field('Name'), findsOneWidget);
    expect(field('Age in years'), findsOneWidget);
    expect(field('Height'), findsOneWidget);
    expect(field('Current weight'), findsOneWidget);
    expect(find.text('Save profile'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
  });

  // Test 2: Initial user name
  testWidgets('displays the initial user name', (tester) async {
    await loadScreen(tester, initialName: 'Trailblazer User');

    final nameField = tester.widget<TextFormField>(field('Name'));

    expect(nameField.controller!.text, 'Trailblazer User');
  });

  // Test 3: Edit profile mode
  testWidgets('displays edit profile mode', (tester) async {
    await loadScreen(tester, openedFromProfile: true);

    expect(find.text('Edit profile'), findsOneWidget);

    expect(find.text('Set up your profile'), findsNothing);

    expect(find.text('Save profile'), findsOneWidget);
    expect(find.text('Skip for now'), findsNothing);
  });

  // Test 4: Previously saved profile information
  testWidgets('loads previously saved profile information', (tester) async {
    await loadScreen(
      tester,
      savedProfile: {
        'name': 'Existing User',
        'ageYears': 28,
        'heightCm': 175,
        'weightKg': 75,
        'targetWeightKg': 70,
        'calorieTarget': 2200,
        'bodyGoal': 'lose',
      },
    );

    final isMetric = AppSettings.instance.isMetric;

    expect(
      tester.widget<TextFormField>(field('Name')).controller!.text,
      'Existing User',
    );

    expect(
      tester.widget<TextFormField>(field('Age in years')).controller!.text,
      '28',
    );

    expect(
      tester.widget<TextFormField>(field('Height')).controller!.text,
      isMetric ? '175.0' : (175 / 2.54).toStringAsFixed(1),
    );

    expect(
      tester.widget<TextFormField>(field('Current weight')).controller!.text,
      isMetric ? '75.0' : (75 * 2.2046226218).toStringAsFixed(1),
    );

    expect(
      tester
          .widget<TextFormField>(field('Target weight (optional)'))
          .controller!
          .text,
      isMetric ? '70.0' : (70 * 2.2046226218).toStringAsFixed(1),
    );

    expect(
      tester
          .widget<TextFormField>(field('Daily calorie target (optional)'))
          .controller!
          .text,
      '2200',
    );

    expect(find.text('Lose weight'), findsWidgets);
  });

  // Test 5: Empty name validation
  testWidgets('rejects an empty name', (tester) async {
    await loadScreen(tester, initialName: '');

    await validateForm(tester);

    expect(find.text('Enter your name.'), findsOneWidget);
  });

  // Test 6: Minimum age validation
  testWidgets('rejects age below 18', (tester) async {
    await loadScreen(tester);

    await enterField(tester, 'Age in years', '17');

    await validateForm(tester);

    expect(
      find.text('Enter a whole-number age from 18 to 120.'),
      findsOneWidget,
    );
  });

  // Test 7: Maximum age validation
  testWidgets('rejects age above 120', (tester) async {
    await loadScreen(tester);

    await enterField(tester, 'Age in years', '121');

    await validateForm(tester);

    expect(
      find.text('Enter a whole-number age from 18 to 120.'),
      findsOneWidget,
    );
  });

  // Test 8: Invalid height validation
  testWidgets('rejects zero height', (tester) async {
    await loadScreen(tester, savedProfile: validProfile);

    await enterField(tester, 'Height', '0');

    await validateForm(tester);

    expect(
      find.descendant(
        of: field('Height'),
        matching: find.text('Enter a number greater than zero.'),
      ),
      findsOneWidget,
    );
  });

  // Test 9: Invalid current weight validation
  testWidgets('rejects negative current weight', (tester) async {
    await loadScreen(tester, savedProfile: validProfile);

    await enterField(tester, 'Current weight', '-75');

    await validateForm(tester);

    expect(
      find.descendant(
        of: field('Current weight'),
        matching: find.text('Enter a number greater than zero.'),
      ),
      findsOneWidget,
    );
  });

  // Test 10: Invalid target weight validation
  testWidgets('rejects negative target weight', (tester) async {
    await loadScreen(tester, savedProfile: validProfile);

    await enterField(tester, 'Target weight (optional)', '-10');

    await validateForm(tester);

    expect(
      find.descendant(
        of: field('Target weight (optional)'),
        matching: find.text('Enter a number greater than zero.'),
      ),
      findsOneWidget,
    );
  });

  // Test 11: Invalid calorie target validation
  testWidgets('rejects negative calorie target', (tester) async {
    await loadScreen(tester, savedProfile: validProfile);

    await enterField(tester, 'Daily calorie target (optional)', '-200');

    await validateForm(tester);

    expect(find.text('Enter a positive whole number.'), findsOneWidget);
  });

  // Test 12: Incomplete calorie estimate information
  testWidgets('rejects incomplete calorie estimate information', (
    tester,
  ) async {
    await loadScreen(tester);

    await tapWidget(tester, find.text('Calculate suggestion'));

    expect(
      find.textContaining('Check your age, height, and weight.'),
      findsOneWidget,
    );

    expect(find.textContaining('Suggested daily target:'), findsNothing);
  });

  // Test 13: Calorie estimate eligibility checkbox
  testWidgets('toggles calorie estimate eligibility', (tester) async {
    await loadScreen(tester);

    final checkbox = find.byType(CheckboxListTile);

    expect(checkbox, findsOneWidget);

    expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);

    await tapWidget(tester, checkbox);

    expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);

    await tapWidget(tester, checkbox);

    expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
  });

  // Test 14: Calculate and apply calorie suggestion
  testWidgets('calculates and applies a calorie suggestion', (tester) async {
    await loadScreen(tester, savedProfile: validProfile);

    await tapWidget(tester, find.byType(CheckboxListTile));

    await tapWidget(tester, find.text('Calculate suggestion'));

    expect(find.text('Suggested daily target: 2700 kcal'), findsOneWidget);

    expect(find.text('Use suggestion'), findsOneWidget);

    await tapWidget(tester, find.text('Use suggestion'));

    final calorieField = tester.widget<TextFormField>(
      field('Daily calorie target (optional)'),
    );

    expect(calorieField.controller!.text, '2700');
  });

  // Test 15: Skip profile setup and navigate home
  testWidgets('navigates home when profile setup is skipped', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, find.text('Skip for now'));

    expect(find.text('Home Screen'), findsOneWidget);

    expect(find.byType(ProfileSetupScreen), findsNothing);
  });
}
