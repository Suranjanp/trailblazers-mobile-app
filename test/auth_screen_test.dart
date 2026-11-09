import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_ap_1/main.dart';

void main() {
  testWidgets('Signup rejects mismatched passwords', (tester) async {
    await tester.pumpWidget(const TrailblazerApp());
    await tester.tap(find.text('Sign Up').first);
    await tester.pumpAndSettle();

    Future<void> enter(int index, String value) async {
      final field = find.byType(TextFormField).at(index);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }

    await enter(0, 'Alex');
    await enter(1, 'alex@example.com');
    await enter(2, 'sample-password');
    await enter(3, 'different-password');

    final submit = find.widgetWithText(FilledButton, 'Create Account');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Passwords must match.'), findsOneWidget);
    expect(find.text('Trailblazer · Home'), findsNothing);
  });
}
