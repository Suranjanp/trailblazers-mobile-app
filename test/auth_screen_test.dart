import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_ap_1/main.dart';

void main() {
  testWidgets('Signup rejects mismatched passwords', (tester) async {
    await tester.pumpWidget(const TrailblazerApp());
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    Future<void> enter(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }

    await enter('Name', 'Alex');
    await enter('Email', 'alex@example.com');
    await enter('Password', 'sample-password');
    await enter('Confirm password', 'different-password');

    final submit = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Passwords must match.'), findsOneWidget);
    expect(find.text('Trailblazer · Home'), findsNothing);
  });
}
