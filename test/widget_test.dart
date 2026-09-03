import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:masapp/app.dart';

void main() {
  testWidgets('MasApp initializes and displays splash screen cleanly', (
    WidgetTester tester,
  ) async {
    // Set a desktop-sized test viewport
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Build our app and trigger an initial frame
    await tester.pumpWidget(const ProviderScope(child: MasApp()));

    // Verify that the initial frame renders the splash/loading state
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('กำลังเชื่อมต่อฐานข้อมูล...'), findsOneWidget);
  });
}
