import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_ap_1/screens/main_screen.dart';

void main() {
  testWidgets('User can navigate from Home to Profile', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MainScreen(
          profileScreen: Center(child: Text('Profile test content')),
        ),
      ),
    );

    expect(find.text('Trailblazer · Home'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    final profile = find.widgetWithText(NavigationDrawerDestination, 'Profile');
    await tester.ensureVisible(profile);
    await tester.tap(profile);
    await tester.pumpAndSettle();

    expect(find.text('Trailblazer · Profile'), findsOneWidget);
    expect(find.text('Profile test content'), findsOneWidget);
  });
}