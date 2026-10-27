import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Imports the app using the package name from pubspec.yaml.
import 'package:test_ap_1/main.dart';

void main() {
  testWidgets('User can navigate from Home to Profile', (tester) async {
    await tester.pumpWidget(const TrailblazerApp());

    expect(find.text('Trailblazer · Home'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(NavigationDrawerDestination, 'Profile'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trailblazer · Profile'), findsOneWidget);
    expect(
      find.text('Manage your personal information and daily targets.'),
      findsOneWidget,
    );
  });
}
