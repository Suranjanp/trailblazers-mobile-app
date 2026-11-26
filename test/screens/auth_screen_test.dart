import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:test_ap_1/screens/auth_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> loadScreen(
    WidgetTester tester, {
    bool signUp = false,
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
        home: AuthScreen(signUp: signUp),
      ),
    );

    await tester.pumpAndSettle();
  }

  Finder field(String hint) {
    return find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == hint,
    );
  }

  Future<void> tapWidget(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterField(
    WidgetTester tester,
    String hint,
    String value,
  ) async {
    final finder = field(hint);

    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pumpAndSettle();
  }

  Future<void> submitForm(WidgetTester tester) async {
    await tapWidget(tester, find.byType(FilledButton));
  }

  String fieldValue(WidgetTester tester, String hint) {
    return tester.widget<TextField>(field(hint)).controller!.text;
  }

  // Test 1: Screen initialization
  testWidgets('renders AuthScreen successfully', (tester) async {
    await loadScreen(tester);

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(Form), findsOneWidget);

    expect(find.text('Learn. Plan. Achieve.'), findsOneWidget);

    expect(find.text('Continue as Guest'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  // Test 2: Default login mode
  testWidgets('displays login mode by default', (tester) async {
    await loadScreen(tester);

    expect(field('Email Address'), findsOneWidget);
    expect(field('Password'), findsOneWidget);

    expect(field('Name'), findsNothing);
    expect(field('Confirm Password'), findsNothing);

    expect(find.byType(TextFormField), findsNWidgets(2));

    expect(find.widgetWithText(FilledButton, 'Log In'), findsOneWidget);

    expect(find.text('Remember Me'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
  });

  // Test 3: Initial signup mode
  testWidgets('opens account creation mode when signUp is true', (
    tester,
  ) async {
    await loadScreen(tester, signUp: true);

    expect(find.text('Create Account'), findsNWidgets(2));

    expect(field('Name'), findsOneWidget);
    expect(field('Email Address'), findsOneWidget);
    expect(field('Password'), findsOneWidget);
    expect(field('Confirm Password'), findsOneWidget);

    expect(find.byType(TextFormField), findsNWidgets(4));

    expect(find.text('Remember Me'), findsNothing);
    expect(find.text('Forgot Password?'), findsNothing);
  });

  // Test 4: Switch from login to signup
  testWidgets('switches from login to signup using top tab', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, find.text('Sign Up').first);

    expect(field('Name'), findsOneWidget);
    expect(field('Confirm Password'), findsOneWidget);

    expect(find.widgetWithText(FilledButton, 'Create Account'), findsOneWidget);

    expect(find.byType(Checkbox), findsNothing);
  });

  // Test 5: Switch from signup to login
  testWidgets('switches from signup to login using top tab', (tester) async {
    await loadScreen(tester, signUp: true);

    await tapWidget(tester, find.text('Log In').first);

    expect(field('Name'), findsNothing);
    expect(field('Confirm Password'), findsNothing);

    expect(find.byType(TextFormField), findsNWidgets(2));

    expect(find.widgetWithText(FilledButton, 'Log In'), findsOneWidget);

    expect(find.byType(Checkbox), findsOneWidget);
  });

  // Test 6: Alternate signup link
  testWidgets('switches to signup using bottom signup link', (tester) async {
    await loadScreen(tester);

    expect(find.text("Don't have an account? "), findsOneWidget);

    await tapWidget(tester, find.text('Sign Up').last);

    expect(field('Name'), findsOneWidget);
    expect(field('Confirm Password'), findsOneWidget);

    expect(find.text('Already have an account? '), findsOneWidget);
  });

  // Test 7: Alternate login link
  testWidgets('switches to login using bottom login link', (tester) async {
    await loadScreen(tester, signUp: true);

    await tapWidget(tester, find.text('Log In').last);

    expect(field('Name'), findsNothing);
    expect(field('Confirm Password'), findsNothing);

    expect(find.text("Don't have an account? "), findsOneWidget);

    expect(find.text('Remember Me'), findsOneWidget);
  });

  // Test 8: Empty login form
  testWidgets('rejects empty login credentials', (tester) async {
    await loadScreen(tester);

    await submitForm(tester);

    expect(find.text('Enter a valid email address.'), findsOneWidget);

    expect(find.text('Enter your password.'), findsOneWidget);

    expect(find.byType(AuthScreen), findsOneWidget);

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  // Test 9: Invalid email address
  testWidgets('rejects invalid email address', (tester) async {
    await loadScreen(tester);

    await enterField(tester, 'Email Address', 'invalid-email');

    await enterField(tester, 'Password', 'Password123');

    await submitForm(tester);

    expect(find.text('Enter a valid email address.'), findsOneWidget);

    expect(find.text('Enter your password.'), findsNothing);
  });

  // Test 10: Missing password
  testWidgets('rejects login when password is empty', (tester) async {
    await loadScreen(tester);

    await enterField(tester, 'Email Address', 'student@example.com');

    await submitForm(tester);

    expect(find.text('Enter your password.'), findsOneWidget);

    expect(find.text('Enter a valid email address.'), findsNothing);
  });

  // Test 11: Empty signup form
  testWidgets('rejects empty account creation form', (tester) async {
    await loadScreen(tester, signUp: true);

    await submitForm(tester);

    expect(find.text('Enter your name.'), findsOneWidget);

    expect(find.text('Enter a valid email address.'), findsOneWidget);

    expect(find.text('Enter your password.'), findsOneWidget);

    expect(find.text('Passwords must match.'), findsOneWidget);
  });

  // Test 12: Whitespace-only name
  testWidgets('rejects whitespace-only account name', (tester) async {
    await loadScreen(tester, signUp: true);

    await enterField(tester, 'Name', '   ');

    await enterField(tester, 'Email Address', 'student@example.com');

    await enterField(tester, 'Password', 'Password123');

    await enterField(tester, 'Confirm Password', 'Password123');

    await submitForm(tester);

    expect(find.text('Enter your name.'), findsOneWidget);

    expect(find.text('Passwords must match.'), findsNothing);
  });

  // Test 13: Short signup password
  testWidgets('rejects signup password shorter than eight characters', (
    tester,
  ) async {
    await loadScreen(tester, signUp: true);

    await enterField(tester, 'Name', 'Test Student');

    await enterField(tester, 'Email Address', 'student@example.com');

    await enterField(tester, 'Password', '1234567');

    await enterField(tester, 'Confirm Password', '1234567');

    await submitForm(tester);

    expect(find.text('Use at least 8 characters.'), findsOneWidget);

    expect(find.text('Passwords must match.'), findsNothing);
  });

  // Test 14: Password confirmation mismatch
  testWidgets('rejects mismatched signup passwords', (tester) async {
    await loadScreen(tester, signUp: true);

    await enterField(tester, 'Name', 'Test Student');

    await enterField(tester, 'Email Address', 'student@example.com');

    await enterField(tester, 'Password', 'Password123');

    await enterField(tester, 'Confirm Password', 'Different123');

    await submitForm(tester);

    expect(find.text('Passwords must match.'), findsOneWidget);

    expect(find.text('Use at least 8 characters.'), findsNothing);
  });

  // Test 15: Password visibility
  testWidgets('toggles password visibility correctly', (tester) async {
    await loadScreen(tester, signUp: true);

    expect(tester.widget<TextField>(field('Password')).obscureText, isTrue);

    expect(
      tester.widget<TextField>(field('Confirm Password')).obscureText,
      isTrue,
    );

    await tapWidget(tester, find.byTooltip('Show password'));

    expect(tester.widget<TextField>(field('Password')).obscureText, isFalse);

    // Confirmation field must remain hidden.
    expect(
      tester.widget<TextField>(field('Confirm Password')).obscureText,
      isTrue,
    );

    await tapWidget(tester, find.byTooltip('Hide password'));

    expect(tester.widget<TextField>(field('Password')).obscureText, isTrue);
  });

  // Test 16: Remember Me checkbox
  testWidgets('toggles Remember Me checkbox', (tester) async {
    await loadScreen(tester);

    final checkbox = find.byType(Checkbox);

    expect(tester.widget<Checkbox>(checkbox).value, isFalse);

    await tapWidget(tester, checkbox);

    expect(tester.widget<Checkbox>(checkbox).value, isTrue);

    await tapWidget(tester, checkbox);

    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
  });

  // Test 17: Password reset with empty email
  testWidgets('rejects password reset without email address', (tester) async {
    await loadScreen(tester);

    await tapWidget(tester, find.text('Forgot Password?'));

    expect(find.text('Enter your email address first.'), findsOneWidget);

    expect(find.byType(SnackBar), findsOneWidget);
  });

  // Test 18: Password reset with invalid email
  testWidgets('rejects password reset with invalid email address', (
    tester,
  ) async {
    await loadScreen(tester);

    await enterField(tester, 'Email Address', 'invalid-email');

    await tapWidget(tester, find.text('Forgot Password?'));

    expect(find.text('Enter your email address first.'), findsOneWidget);

    expect(find.byType(SnackBar), findsOneWidget);
  });

  // Test 19: Clear passwords when switching modes
  testWidgets('clears password fields when authentication mode changes', (
    tester,
  ) async {
    await loadScreen(tester, signUp: true);

    await enterField(tester, 'Password', 'Password123');

    await enterField(tester, 'Confirm Password', 'Password123');

    expect(fieldValue(tester, 'Password'), 'Password123');

    expect(fieldValue(tester, 'Confirm Password'), 'Password123');

    // Switch to login.
    await tapWidget(tester, find.text('Log In').first);

    expect(fieldValue(tester, 'Password'), isEmpty);

    expect(field('Confirm Password'), findsNothing);

    // Switch back to signup.
    await tapWidget(tester, find.text('Sign Up').first);

    expect(fieldValue(tester, 'Password'), isEmpty);

    expect(fieldValue(tester, 'Confirm Password'), isEmpty);
  });

  // Test 20: Dark mode and screen lifecycle
  testWidgets('renders in dark mode and disposes successfully', (tester) async {
    await loadScreen(tester, themeMode: ThemeMode.dark);

    final authFinder = find.byType(AuthScreen);
    final state = tester.state(authFinder);

    expect(state.mounted, isTrue);

    expect(Theme.of(tester.element(authFinder)).brightness, Brightness.dark);

    expect(field('Email Address'), findsOneWidget);
    expect(field('Password'), findsOneWidget);

    expect(find.text('Continue as Guest'), findsOneWidget);

    expect(tester.takeException(), isNull);

    // Remove the screen to verify disposal.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    await tester.pumpAndSettle();

    expect(state.mounted, isFalse);
    expect(find.byType(AuthScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
