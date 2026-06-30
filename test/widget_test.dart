import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finalyearproject/screens/signup_screen.dart';

void main() {
  testWidgets('Signup choice page renders role options', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupChoicePage()));

    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
    expect(find.text('Passenger'), findsOneWidget);
  });
}
