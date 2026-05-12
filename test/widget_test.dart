// Basic smoke test for PRISM app launch.
//
// This just verifies the app widget can be instantiated without errors.
// Camera/pose detection tests require a device and can't run in unit tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/main.dart';

void main() {
  testWidgets('App launches without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const PrismTestApp());

    // Verify the app title appears
    expect(find.text('PRISM – Pose Detection Test'), findsOneWidget);
  });
}
