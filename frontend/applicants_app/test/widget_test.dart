import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:applicants_app/features/auth/login_screen.dart';

void main() {
  testWidgets('login screen renders', (tester) async {
    // Pump the screen directly: the app-level router may bypass login while
    // kAutoLoginForTesting is on, but the widget itself must still render.
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: LoginScreen()),
    ));
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Applicants Info System'), findsOneWidget);
  });
}
