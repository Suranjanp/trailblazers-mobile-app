// ignore_for_file: depend_on_referenced_packages

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_ap_1/screens/nutrition_screen.dart';

void main() {
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  Future<void> loadScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NutritionScreen())),
    );

    await tester.pumpAndSettle();
  }

  // Test 1: Signed-out screen rendering
  testWidgets('displays sign-in message to signed-out users', (tester) async {
    await loadScreen(tester);

    expect(find.text('Sign in to track your meals.'), findsOneWidget);

    expect(find.byType(NutritionScreen), findsOneWidget);
  });

  // Test 2: Food logging restriction
  testWidgets('hides add food button from signed-out users', (tester) async {
    await loadScreen(tester);

    expect(find.text('Add food'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  // Test 3: Calorie summary restriction
  testWidgets('hides calorie summary from signed-out users', (tester) async {
    await loadScreen(tester);

    expect(find.text('Calories today'), findsNothing);
    expect(find.textContaining('kcal'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  // Test 4: Food log restriction
  testWidgets('hides daily food log from signed-out users', (tester) async {
    await loadScreen(tester);

    expect(find.text('Today’s food log'), findsNothing);
    expect(find.text('No food logged today.'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  // Test 5: Meal category restriction
  testWidgets('hides meal categories from signed-out users', (tester) async {
    await loadScreen(tester);

    const mealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snack', 'Other'];

    for (final meal in mealTypes) {
      expect(find.text(meal), findsNothing);
    }
  });

  // Test 6: Calorie target restriction
  testWidgets('hides daily calorie target and progress indicator', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.text('Set a daily calorie target in Profile.'), findsNothing);

    expect(find.textContaining('kcal remaining'), findsNothing);

    expect(find.textContaining('kcal over target'), findsNothing);

    expect(find.text('Target met'), findsNothing);

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  // Test 7: Food entry form restriction
  testWidgets('does not display food entry form when signed out', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextFormField), findsNothing);

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    expect(find.text('Food name'), findsNothing);
    expect(find.text('Servings'), findsNothing);
    expect(find.text('Calories per serving'), findsNothing);
    expect(find.text('Save food'), findsNothing);
  });

  // Test 8: Loading state verification
  testWidgets('does not display loading indicators when signed out', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);

    expect(find.byType(LinearProgressIndicator), findsNothing);

    expect(find.text('Loading calorie target…'), findsNothing);
  });

  // Test 9: Error state verification
  testWidgets('does not display food log errors when signed out', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.text('Could not load your food log.'), findsNothing);

    expect(find.text('Could not load your calorie target.'), findsNothing);

    expect(find.textContaining('Could not save food'), findsNothing);
  });

  // Test 10: Signed-out screen stability
  testWidgets('maintains signed-out state after rebuilding', (tester) async {
    await loadScreen(tester);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NutritionScreen())),
    );

    await tester.pumpAndSettle();

    expect(find.text('Sign in to track your meals.'), findsOneWidget);

    expect(find.text('Add food'), findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
