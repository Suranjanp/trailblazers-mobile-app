 // ignore_for_file: depend_on_referenced_packages

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:test_ap_1/screens/health_hub_screen.dart';
import 'package:test_ap_1/screens/health_screen.dart';
import 'package:test_ap_1/screens/nutrition_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const nutritionMessage = 'Sign in to track your meals.';

  const wellnessMessage =
      'Please sign in to save and view your health history.';

  Future<void> loadScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HealthHubScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  Finder tab(String label) {
    return find.widgetWithText(Tab, label);
  }

  Future<void> selectTab(
    WidgetTester tester,
    String label,
  ) async {
    await tester.tap(tab(label));
    await tester.pumpAndSettle();
  }

  Finder screenStack() {
    return find.descendant(
      of: find.byType(HealthHubScreen),
      matching: find.byType(IndexedStack),
    );
  }

  int selectedIndex(WidgetTester tester) {
    return tester.widget<IndexedStack>(screenStack()).index!;
  }

  // Test 1: Health Hub screen rendering
  testWidgets(
    'renders Health Hub screen successfully',
    (tester) async {
      await loadScreen(tester);

      expect(
        find.byType(HealthHubScreen),
        findsOneWidget,
      );

      expect(find.byType(TabBar), findsOneWidget);
      expect(screenStack(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // Test 2: Tab controller configuration
  testWidgets(
    'configures tab controller with two tabs',
    (tester) async {
      await loadScreen(tester);

      final controller = tester.widget<DefaultTabController>(
        find.byType(DefaultTabController),
      );

      expect(controller.length, 2);
      expect(controller.initialIndex, 0);
    },
  );

  // Test 3: Tab rendering
  testWidgets(
    'displays Nutrition and Wellness tabs',
    (tester) async {
      await loadScreen(tester);

      expect(tab('Nutrition'), findsOneWidget);
      expect(tab('Wellness'), findsOneWidget);

      expect(find.byType(Tab), findsNWidgets(2));
    },
  );

  // Test 4: Tab icons
  testWidgets(
    'displays correct icons for both tabs',
    (tester) async {
      await loadScreen(tester);

      expect(
        find.descendant(
          of: tab('Nutrition'),
          matching: find.byIcon(
            Icons.restaurant_outlined,
          ),
        ),
        findsOneWidget,
      );

      expect(
        find.descendant(
          of: tab('Wellness'),
          matching: find.byIcon(
            Icons.favorite_outline,
          ),
        ),
        findsOneWidget,
      );
    },
  );

  // Test 5: Default selected tab
  testWidgets(
    'selects Nutrition tab by default',
    (tester) async {
      await loadScreen(tester);

      expect(selectedIndex(tester), 0);

      final controller = DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      );

      expect(controller.index, 0);
    },
  );

  // Test 6: IndexedStack child configuration
  testWidgets(
    'contains Nutrition and Health child screens',
    (tester) async {
      await loadScreen(tester);

      final stack = tester.widget<IndexedStack>(
        screenStack(),
      );

      expect(stack.children.length, 2);

      expect(
        stack.children[0],
        isA<NutritionScreen>(),
      );

      expect(
        stack.children[1],
        isA<HealthScreen>(),
      );
    },
  );

  // Test 7: Nutrition screen visibility
  testWidgets(
    'displays Nutrition screen content by default',
    (tester) async {
      await loadScreen(tester);

      expect(
        find.text(nutritionMessage),
        findsOneWidget,
      );

      expect(
        find.text(wellnessMessage),
        findsNothing,
      );

      expect(selectedIndex(tester), 0);
    },
  );

  // Test 8: Wellness navigation
  testWidgets(
    'switches from Nutrition to Wellness',
    (tester) async {
      await loadScreen(tester);

      await selectTab(tester, 'Wellness');

      expect(selectedIndex(tester), 1);

      expect(
        find.text(wellnessMessage),
        findsOneWidget,
      );

      expect(
        find.text(nutritionMessage),
        findsNothing,
      );
    },
  );

  // Test 9: Return to Nutrition
  testWidgets(
    'switches from Wellness back to Nutrition',
    (tester) async {
      await loadScreen(tester);

      await selectTab(tester, 'Wellness');

      expect(selectedIndex(tester), 1);

      await selectTab(tester, 'Nutrition');

      expect(selectedIndex(tester), 0);

      expect(
        find.text(nutritionMessage),
        findsOneWidget,
      );

      expect(
        find.text(wellnessMessage),
        findsNothing,
      );
    },
  );

  // Test 10: Tab controller synchronization
  testWidgets(
    'keeps tab controller and IndexedStack synchronized',
    (tester) async {
      await loadScreen(tester);

      final controller = DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      );

      expect(controller.index, 0);
      expect(selectedIndex(tester), 0);

      await selectTab(tester, 'Wellness');

      expect(controller.index, 1);
      expect(selectedIndex(tester), 1);

      await selectTab(tester, 'Nutrition');

      expect(controller.index, 0);
      expect(selectedIndex(tester), 0);
    },
  );

  // Test 11: Nutrition PageStorageKey
  testWidgets(
    'assigns correct PageStorageKey to Nutrition screen',
    (tester) async {
      await loadScreen(tester);

      final stack = tester.widget<IndexedStack>(
        screenStack(),
      );

      expect(
        stack.children[0].key,
        const PageStorageKey('health-nutrition'),
      );
    },
  );

  // Test 12: Wellness PageStorageKey
  testWidgets(
    'assigns correct PageStorageKey to Wellness screen',
    (tester) async {
      await loadScreen(tester);

      final stack = tester.widget<IndexedStack>(
        screenStack(),
      );

      expect(
        stack.children[1].key,
        const PageStorageKey('health-wellness'),
      );
    },
  );

  // Test 13: Child screen preservation
  testWidgets(
    'preserves child screen instances during tab switching',
    (tester) async {
      await loadScreen(tester);

      final nutritionFinder = find.byType(
        NutritionScreen,
        skipOffstage: false,
      );

      final wellnessFinder = find.byType(
        HealthScreen,
        skipOffstage: false,
      );

      expect(nutritionFinder, findsOneWidget);
      expect(wellnessFinder, findsOneWidget);

      // NutritionScreen is a StatelessWidget.
      // Use element() instead of state().
      final originalNutritionElement =
          tester.element(nutritionFinder);

      final originalWellnessElement =
          tester.element(wellnessFinder);

      // HealthScreen is a StatefulWidget.
      final originalWellnessState =
          tester.state(wellnessFinder);

      await selectTab(tester, 'Wellness');

      expect(selectedIndex(tester), 1);

      expect(
        tester.element(nutritionFinder),
        same(originalNutritionElement),
      );

      expect(
        tester.element(wellnessFinder),
        same(originalWellnessElement),
      );

      expect(
        tester.state(wellnessFinder),
        same(originalWellnessState),
      );

      await selectTab(tester, 'Nutrition');

      expect(selectedIndex(tester), 0);

      expect(
        tester.element(nutritionFinder),
        same(originalNutritionElement),
      );

      expect(
        tester.element(wellnessFinder),
        same(originalWellnessElement),
      );

      expect(
        tester.state(wellnessFinder),
        same(originalWellnessState),
      );

      expect(originalNutritionElement.mounted, isTrue);
      expect(originalWellnessElement.mounted, isTrue);

      expect(tester.takeException(), isNull);
    },
  );

  // Test 14: Repeated tab switching
  testWidgets(
    'handles repeated tab switching without crashing',
    (tester) async {
      await loadScreen(tester);

      for (int i = 0; i < 3; i++) {
        await selectTab(tester, 'Wellness');

        expect(selectedIndex(tester), 1);

        expect(
          find.text(wellnessMessage),
          findsOneWidget,
        );

        await selectTab(tester, 'Nutrition');

        expect(selectedIndex(tester), 0);

        expect(
          find.text(nutritionMessage),
          findsOneWidget,
        );
      }

      expect(tester.takeException(), isNull);
    },
  );

  // Test 15: Automatic keep-alive behavior
  // Tests actual state preservation without accessing
  // the protected wantKeepAlive member.
  testWidgets(
    'preserves Health Hub state when moved offscreen',
    (tester) async {
      final controller = PageController();

      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: controller,
              children: const [
                HealthHubScreen(),
                Center(
                  child: Text('Other page'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Select Wellness before leaving the Health Hub.
      await selectTab(tester, 'Wellness');

      final originalState = tester.state(
        find.byType(HealthHubScreen),
      );

      expect(originalState.mounted, isTrue);
      expect(selectedIndex(tester), 1);

      expect(
        find.text(wellnessMessage),
        findsOneWidget,
      );

      // Navigate away from the Health Hub.
      controller.jumpToPage(1);

      await tester.pumpAndSettle();

      expect(
        find.text('Other page'),
        findsOneWidget,
      );

      // Verify that the original state remains mounted.
      expect(originalState.mounted, isTrue);

      // Return to the Health Hub.
      controller.jumpToPage(0);

      await tester.pumpAndSettle();

      expect(
        find.byType(HealthHubScreen),
        findsOneWidget,
      );

      // Verify that the original state was preserved.
      expect(
        tester.state(find.byType(HealthHubScreen)),
        same(originalState),
      );

      // Verify that Wellness is still selected.
      expect(selectedIndex(tester), 1);

      final tabController = DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      );

      expect(tabController.index, 1);

      expect(
        find.text(wellnessMessage),
        findsOneWidget,
      );

      expect(
        find.text(nutritionMessage),
        findsNothing,
      );

      expect(tester.takeException(), isNull);

      // Remove the PageView before disposing its controller.
      await tester.pumpWidget(
        const SizedBox.shrink(),
      );

      await tester.pumpAndSettle();

      expect(originalState.mounted, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}