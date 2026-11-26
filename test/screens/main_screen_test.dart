// ignore_for_file: depend_on_referenced_packages

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:test_ap_1/screens/main_screen.dart';
import 'package:test_ap_1/services/app_settings.dart';
import 'package:test_ap_1/services/notification_settings.dart';

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

  // Common screen initialization
  Future<void> loadScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: MainScreen(
          profileScreen: Scaffold(
            body: Center(child: Text('Test Profile Screen')),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  // Common tap function
  Future<void> tapWidget(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tapWidget(tester, find.byTooltip('Quick settings'));
  }

  Future<void> openQuote(WidgetTester tester) async {
    await tapWidget(tester, find.byTooltip('Get inspired'));
  }

  Finder mainScaffold() {
    return find.byWidgetPredicate(
      (widget) =>
          widget is Scaffold &&
          widget.endDrawer != null &&
          widget.bottomNavigationBar != null,
    );
  }

  Finder bottomNavigation(String label) {
    return find
        .descendant(
          of: mainScaffold(),
          matching: find.widgetWithText(InkWell, label),
        )
        .last;
  }

  Finder drawerSwitch(String label) {
    return find.descendant(
      of: find.byType(Drawer),
      matching: find.widgetWithText(SwitchListTile, label),
    );
  }

  Finder drawerText(String label) {
    return find.descendant(of: find.byType(Drawer), matching: find.text(label));
  }

  Finder notificationDropdown() {
    return find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(DropdownButtonFormField<int>),
    );
  }

  Finder quoteText() {
    return find.descendant(
      of: find.byType(Dialog),
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data?.startsWith('“') ?? false),
      ),
    );
  }

  // Test 1: Main screen rendering
  testWidgets('displays main screen with Home selected', (tester) async {
    await loadScreen(tester);

    expect(find.byType(MainScreen), findsOneWidget);

    expect(find.text('Trailblazer · Home'), findsOneWidget);

    expect(find.byType(PageView), findsOneWidget);

    expect(find.byTooltip('Quick settings'), findsOneWidget);

    expect(find.byTooltip('Get inspired'), findsOneWidget);
  }, variant: platformVariant);

  // Test 2: Bottom navigation destinations
  testWidgets('displays four primary navigation destinations', (tester) async {
    await loadScreen(tester);

    expect(bottomNavigation('Home'), findsOneWidget);

    expect(bottomNavigation('Schedule'), findsOneWidget);

    expect(bottomNavigation('Health'), findsOneWidget);

    expect(bottomNavigation('Fitness'), findsOneWidget);
  }, variant: platformVariant);

  // Test 3: Bottom navigation icons
  testWidgets('displays correct bottom navigation icons', (tester) async {
    await loadScreen(tester);

    const destinations = {
      'Home': Icons.home_outlined,
      'Schedule': Icons.calendar_month_outlined,
      'Health': Icons.favorite_outline,
      'Fitness': Icons.fitness_center,
    };

    for (final entry in destinations.entries) {
      expect(
        find.descendant(
          of: bottomNavigation(entry.key),
          matching: find.byIcon(entry.value),
        ),
        findsOneWidget,
      );
    }
  }, variant: platformVariant);

  // Test 4: Schedule navigation
  testWidgets('navigates to Schedule screen', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, bottomNavigation('Schedule'));

    expect(find.text('Trailblazer · Schedule'), findsOneWidget);
  }, variant: platformVariant);

  // Test 5: Health navigation
  testWidgets('navigates to Health screen', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, bottomNavigation('Health'));

    expect(find.text('Trailblazer · Health'), findsOneWidget);
  }, variant: platformVariant);

  // Test 6: Fitness navigation
  testWidgets('navigates to Fitness screen', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, bottomNavigation('Fitness'));

    expect(find.text('Trailblazer · Fitness'), findsOneWidget);
  }, variant: platformVariant);

  // Test 7: Return to Home
  testWidgets('returns to Home screen using bottom navigation', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, bottomNavigation('Schedule'));

    expect(find.text('Trailblazer · Schedule'), findsOneWidget);

    await tapWidget(tester, bottomNavigation('Home'));

    expect(find.text('Trailblazer · Home'), findsOneWidget);
  }, variant: platformVariant);

  // Test 8: Selected navigation item
  testWidgets('updates selected navigation item', (tester) async {
    await loadScreen(tester);

    final homeLabel = find.descendant(
      of: bottomNavigation('Home'),
      matching: find.text('Home'),
    );

    expect(tester.widget<Text>(homeLabel).style?.fontWeight, FontWeight.bold);

    await tapWidget(tester, bottomNavigation('Schedule'));

    final scheduleLabel = find.descendant(
      of: bottomNavigation('Schedule'),
      matching: find.text('Schedule'),
    );

    expect(
      tester.widget<Text>(scheduleLabel).style?.fontWeight,
      FontWeight.bold,
    );

    expect(tester.widget<Text>(homeLabel).style?.fontWeight, FontWeight.normal);
  }, variant: platformVariant);

  // Test 9: Open Quick Settings
  testWidgets('opens Quick Settings drawer', (tester) async {
    await loadScreen(tester);
    await openSettings(tester);

    expect(find.byType(Drawer), findsOneWidget);

    expect(drawerText('Quick Settings'), findsOneWidget);

    expect(drawerText('PREFERENCES'), findsOneWidget);

    expect(drawerText('NOTIFICATIONS'), findsOneWidget);

    expect(drawerText('ACCOUNT'), findsOneWidget);

    expect(drawerText('SESSION'), findsOneWidget);

    expect(tester.state<ScaffoldState>(mainScaffold()).isEndDrawerOpen, isTrue);
  }, variant: platformVariant);

  // Test 10: Close Quick Settings
  testWidgets('closes Quick Settings drawer', (tester) async {
    await loadScreen(tester);
    await openSettings(tester);

    await tapWidget(tester, find.byTooltip('Close settings'));

    final scaffold = tester.state<ScaffoldState>(mainScaffold());

    expect(scaffold.isEndDrawerOpen, isFalse);

    expect(find.text('Trailblazer · Home'), findsOneWidget);
  }, variant: platformVariant);

  // Test 11: Measurement unit options
  testWidgets('displays metric and imperial measurement options', (
    tester,
  ) async {
    await loadScreen(tester);
    await openSettings(tester);

    expect(drawerText('Measurement units'), findsOneWidget);

    expect(drawerText('Metric'), findsOneWidget);

    expect(drawerText('Imperial'), findsOneWidget);

    expect(find.byType(SegmentedButton<MeasurementSystem>), findsOneWidget);
  }, variant: platformVariant);

  // Test 12: Measurement unit switching
  testWidgets('switches between metric and imperial units', (tester) async {
    await loadScreen(tester);

    final original = AppSettings.instance.measurementSystem;

    try {
      await openSettings(tester);

      await tapWidget(tester, drawerText('Metric'));

      expect(AppSettings.instance.isMetric, isTrue);

      expect(
        drawerText('Kilometers, kilograms, and centimeters'),
        findsOneWidget,
      );

      await tapWidget(tester, drawerText('Imperial'));

      expect(AppSettings.instance.isMetric, isFalse);

      expect(drawerText('Miles, pounds, and feet/inches'), findsOneWidget);
    } finally {
      await Future.sync(
        () => AppSettings.instance.setMeasurementSystem(original),
      );

      await tester.pump();
    }
  }, variant: platformVariant);

  // Test 13: Dark mode switching
  testWidgets('toggles dark mode preference', (tester) async {
    await loadScreen(tester);

    final original = AppSettings.instance.isDarkMode;

    try {
      await openSettings(tester);

      final darkMode = drawerSwitch('Dark mode');

      expect(tester.widget<SwitchListTile>(darkMode).value, original);

      await tapWidget(tester, darkMode);

      expect(AppSettings.instance.isDarkMode, !original);

      expect(tester.widget<SwitchListTile>(darkMode).value, !original);

      await tapWidget(tester, darkMode);

      expect(AppSettings.instance.isDarkMode, original);
    } finally {
      await Future.sync(() => AppSettings.instance.setDarkMode(original));

      await tester.pump();
    }
  }, variant: platformVariant);

  // Test 14: Notification settings rendering
  testWidgets('displays notification settings', (tester) async {
    await loadScreen(tester);
    await openSettings(tester);

    expect(drawerSwitch('Notifications'), findsOneWidget);

    expect(drawerSwitch('Schedule reminders'), findsOneWidget);

    expect(drawerSwitch('Daily summary'), findsOneWidget);

    expect(drawerSwitch('Motivation'), findsOneWidget);

    expect(drawerText('Reminder lead time'), findsOneWidget);

    expect(notificationDropdown(), findsOneWidget);
  }, variant: platformVariant);

  // Test 15: Notification control state
  testWidgets('notification controls reflect global notification setting', (
    tester,
  ) async {
    await loadScreen(tester);
    await openSettings(tester);

    final enabled = NotificationSettings.instance.enabled;

    const labels = ['Schedule reminders', 'Daily summary', 'Motivation'];

    for (final label in labels) {
      final tile = tester.widget<SwitchListTile>(drawerSwitch(label));

      expect(tile.onChanged != null, enabled);
    }

    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      notificationDropdown(),
    );

    expect(dropdown.onChanged != null, enabled);
  }, variant: platformVariant);

  // Test 16: Profile navigation
  testWidgets('opens profile screen from Quick Settings', (tester) async {
    await loadScreen(tester);
    await openSettings(tester);

    await tapWidget(tester, drawerText('Profile'));

    expect(find.text('Trailblazer · Profile'), findsOneWidget);

    expect(find.text('Test Profile Screen'), findsOneWidget);
  }, variant: platformVariant);

  // Test 17: Inspirational quote dialog
  testWidgets('opens inspirational quote dialog', (tester) async {
    await loadScreen(tester);
    await openQuote(tester);

    expect(find.text('A MOMENT OF INSPIRATION'), findsOneWidget);

    expect(find.text('Keep Moving Forward'), findsOneWidget);

    expect(find.text('Another Quote'), findsOneWidget);

    expect(quoteText(), findsOneWidget);
  }, variant: platformVariant);

  // Test 18: Generate another quote
  testWidgets('displays a different inspirational quote', (tester) async {
    await loadScreen(tester);
    await openQuote(tester);

    final firstQuote = tester.widget<Text>(quoteText()).data;

    await tapWidget(tester, find.text('Another Quote'));

    final secondQuote = tester.widget<Text>(quoteText()).data;

    expect(firstQuote, isNotNull);
    expect(secondQuote, isNotNull);
    expect(secondQuote, isNot(firstQuote));
  }, variant: platformVariant);

  // Test 19: Close inspirational quote dialog
  testWidgets('closes inspirational quote dialog', (tester) async {
    await loadScreen(tester);
    await openQuote(tester);

    await tapWidget(tester, find.text('Keep Moving Forward'));

    expect(find.text('A MOMENT OF INSPIRATION'), findsNothing);

    expect(find.text('Trailblazer · Home'), findsOneWidget);
  }, variant: platformVariant);

  // Test 20: Sign-out confirmation and cancellation
  testWidgets('opens and cancels sign-out confirmation', (tester) async {
    await loadScreen(tester);
    await openSettings(tester);

    await tapWidget(tester, drawerText('Sign out'));

    expect(find.byType(AlertDialog), findsOneWidget);

    expect(find.text('Sign out?'), findsOneWidget);

    expect(
      find.text('You will need to sign in again to access your account.'),
      findsOneWidget,
    );

    expect(find.widgetWithText(FilledButton, 'Sign out'), findsOneWidget);

    await tapWidget(tester, find.widgetWithText(TextButton, 'Cancel'));

    expect(find.byType(AlertDialog), findsNothing);

    expect(find.byType(MainScreen), findsOneWidget);
  }, variant: platformVariant);
}
