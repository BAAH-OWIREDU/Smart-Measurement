import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hackathon_smart_meaurement/main.dart';

void main() {
  testWidgets('Smart Measurements app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartMeasurementsApp());

    expect(find.text('Stand 6ft back'), findsOneWidget);
    expect(find.text('Center body in box'), findsOneWidget);
  });
}