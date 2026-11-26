// ignore_for_file: depend_on_referenced_packages

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:test_ap_1/screens/account_profile_screen.dart';
import 'package:test_ap_1/screens/auth_screen.dart';
import 'package:test_ap_1/screens/profile_setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> loadScreen(
    WidgetTester tester, {
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1400);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: themeMode,
        home: const Scaffold(body: AccountProfileScreen()),
      ),
    );

    await tester.pumpAndSettle();
  }

  Future<void> tapWidget(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder field(String hint) {
    return find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == hint,
    );
  }

  Finder loginButton() {
    return find.widgetWithText(FilledButton, 'Log in');
  }

  Finder createAccountButton() {
    return find.widgetWithText(OutlinedButton, 'Create account');
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
  testWidgets('renders AccountProfileScreen successfully', (tester) async {
    await loadScreen(tester);

    expect(find.byType(AccountProfileScreen), findsOneWidget);

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  // Test 2: Guest profile content
  testWidgets('displays guest profile welcome information', (tester) async {
    await loadScreen(tester);

    expect(find.text('Your profile'), findsOneWidget);

    expect(find.text('Make Trailblazer yours'), findsOneWidget);

    expect(
      find.text(
        'Log in or create an account to manage your goals '
        'and saved profile.',
      ),
      findsOneWidget,
    );

    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  // Test 3: Authentication buttons
  testWidgets('displays login and create account buttons', (tester) async {
    await loadScreen(tester);

    expect(loginButton(), findsOneWidget);

    expect(createAccountButton(), findsOneWidget);

    expect(tester.widget<FilledButton>(loginButton()).onPressed, isNotNull);

    expect(
      tester.widget<OutlinedButton>(createAccountButton()).onPressed,
      isNotNull,
    );
  });

  // Test 4: Authentication button icons
  testWidgets('displays correct authentication button icons', (tester) async {
    await loadScreen(tester);

    expect(
      find.descendant(of: loginButton(), matching: find.byIcon(Icons.login)),
      findsOneWidget,
    );

    expect(
      find.descendant(
        of: createAccountButton(),
        matching: find.byIcon(Icons.person_add_outlined),
      ),
      findsOneWidget,
    );
  });

  // Test 5: Guest account information
  testWidgets('displays guest account record information', (tester) async {
    await loadScreen(tester);

    expect(
      find.text(
        'Logging in opens that account’s records. '
        'Guest records are not automatically merged '
        'into an existing account.',
      ),
      findsOneWidget,
    );
  });

  // Test 6: Login navigation
  testWidgets('navigates to AuthScreen in login mode', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, loginButton());

    expect(find.byType(AuthScreen), findsOneWidget);

    final authScreen = tester.widget<AuthScreen>(find.byType(AuthScreen));

    expect(authScreen.signUp, isFalse);

    expect(find.widgetWithText(FilledButton, 'Log In'), findsOneWidget);

    expect(field('Email Address'), findsOneWidget);
    expect(field('Password'), findsOneWidget);
    expect(field('Name'), findsNothing);

    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  // Test 7: Signup navigation
  testWidgets('navigates to AuthScreen in signup mode', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, createAccountButton());

    expect(find.byType(AuthScreen), findsOneWidget);

    final authScreen = tester.widget<AuthScreen>(find.byType(AuthScreen));

    expect(authScreen.signUp, isTrue);

    expect(find.text('Create Account'), findsNWidgets(2));

    expect(field('Name'), findsOneWidget);
    expect(field('Email Address'), findsOneWidget);
    expect(field('Password'), findsOneWidget);
    expect(field('Confirm Password'), findsOneWidget);

    expect(find.byType(TextFormField), findsNWidgets(4));
  });

  // Test 8: Return from login
  testWidgets('returns to guest profile after closing login', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, loginButton());

    expect(find.byType(AuthScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(AuthScreen))).pop();

    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsNothing);

    expect(find.byType(AccountProfileScreen), findsOneWidget);

    expect(find.text('Make Trailblazer yours'), findsOneWidget);

    expect(loginButton(), findsOneWidget);
    expect(createAccountButton(), findsOneWidget);
  });

  // Test 9: Return from signup
  testWidgets('returns to guest profile after closing signup', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, createAccountButton());

    expect(find.byType(AuthScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(AuthScreen))).pop();

    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsNothing);

    expect(find.byType(AccountProfileScreen), findsOneWidget);

    expect(loginButton(), findsOneWidget);
    expect(createAccountButton(), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  // Test 10: Personalized profile restrictions
  testWidgets('hides personalized profile information when signed out', (
    tester,
  ) async {
    await loadScreen(tester);

    expectHidden([
      'Your goals, your pace.',
      'My profile',
      'My goal',
      'Body details',
      'Weight progress',
      'Account & security',
    ]);

    expect(find.byType(CircleAvatar), findsNothing);
  });

  // Test 11: Fitness and body information restrictions
  testWidgets('hides saved goals and body measurements', (tester) async {
    await loadScreen(tester);

    expectHidden([
      'Lose weight',
      'Gain weight',
      'Maintain weight',
      'Calorie target not set',
      'Target weight',
      'Activity level',
      'Age',
      'Height',
      'Current weight',
      'Starting weight',
      'Change since first check-in',
      'Difference from target',
      'Recent check-ins',
      'No check-ins yet. Save your profile to begin.',
    ]);
  });

  // Test 12: Profile editing restrictions
  testWidgets('hides profile editing and weight update controls', (
    tester,
  ) async {
    await loadScreen(tester);

    expectHidden(['Set up profile', 'Edit profile', 'Update weight']);

    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    expect(find.byIcon(Icons.monitor_weight_outlined), findsNothing);

    expect(find.byType(ProfileSetupScreen), findsNothing);
  });

  // Test 13: Account security restrictions
  testWidgets('hides account security controls for signed-out users', (
    tester,
  ) async {
    await loadScreen(tester);

    expectHidden([
      'Account & security',
      'Reset password',
      'Sign out',
      'Please wait…',
      'Manage your password through your sign-in provider.',
    ]);

    expect(find.byIcon(Icons.logout), findsNothing);

    expect(find.byIcon(Icons.password_outlined), findsNothing);

    expect(find.byType(AlertDialog), findsNothing);
  });

  // Test 14: Loading and error states
  testWidgets('displays guest profile without loading or profile errors', (
    tester,
  ) async {
    await loadScreen(tester);

    expect(find.text('Make Trailblazer yours'), findsOneWidget);

    expect(find.byType(CircularProgressIndicator), findsNothing);

    expect(find.byType(LinearProgressIndicator), findsNothing);

    expect(find.text('Profile unavailable'), findsNothing);

    expect(find.textContaining('Could not load your profile'), findsNothing);

    expect(find.byType(SnackBar), findsNothing);

    expect(tester.takeException(), isNull);
  });

  // Test 15: Dark mode and widget lifecycle
  testWidgets('renders in dark mode and handles screen disposal', (
    tester,
  ) async {
    await loadScreen(tester, themeMode: ThemeMode.dark);

    final profileFinder = find.byType(AccountProfileScreen);

    final originalState = tester.state(profileFinder);

    expect(originalState.mounted, isTrue);

    expect(Theme.of(tester.element(profileFinder)).brightness, Brightness.dark);

    expect(find.text('Make Trailblazer yours'), findsOneWidget);

    expect(loginButton(), findsOneWidget);
    expect(createAccountButton(), findsOneWidget);

    expect(tester.takeException(), isNull);

    // Remove the screen.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    await tester.pumpAndSettle();

    expect(originalState.mounted, isFalse);

    expect(find.byType(AccountProfileScreen), findsNothing);

    // Recreate the screen.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AccountProfileScreen())),
    );

    await tester.pumpAndSettle();

    final newState = tester.state(find.byType(AccountProfileScreen));

    expect(newState.mounted, isTrue);

    expect(newState, isNot(same(originalState)));

    expect(find.text('Make Trailblazer yours'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
