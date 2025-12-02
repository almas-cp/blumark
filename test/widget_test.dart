// Basic Flutter widget test for BluMark app

import 'package:flutter_test/flutter_test.dart';
import 'package:blumark/main.dart';

void main() {
  testWidgets('App launches and shows loading screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BlumarkApp());

    // Verify that the BluMark title is displayed during loading
    expect(find.text('BluMark'), findsOneWidget);
  });
}
