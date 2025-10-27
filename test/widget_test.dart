import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_id_scanner/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen has a title and a capture button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    // Avoid pumpAndSettle; there is a spinning progress indicator during load.
    await tester.pump(const Duration(milliseconds: 50));

    // Title (be robust to any future text tweaks)
    expect(find.textContaining('DITrix'), findsOneWidget);

    // Verify the primary action exists
    expect(find.widgetWithText(FloatingActionButton, 'Capture ID'),
        findsOneWidget);
  });
}
