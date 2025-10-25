import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_id_scanner/screens/home_screen.dart';
import 'package:student_id_scanner/widgets/id_scanner_widget.dart';

void main() {
  testWidgets('HomeScreen has a title and a scanner widget',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    final titleFinder = find.text('Student ID Scanner');
    final scannerWidgetFinder = find.byType(IdScannerWidget);

    expect(titleFinder, findsOneWidget);
    expect(scannerWidgetFinder, findsOneWidget);
  });
}
