import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/home/home_screen.dart';
import 'package:toplinkai_app/onboarding/onboarding_screen.dart';
import 'package:toplinkai_app/onboarding/phone_validation.dart';
import 'package:toplinkai_app/onboarding/service_category.dart';

// The client's phone must be a Canadian / North American number. These are the
// same cases the backend tests (leads.tests.NorthAmericanPhoneTests) use, so
// the two sides can't drift apart.

const _plumbing = ServiceCategory(
  label: 'Plumbing',
  icon: Icons.plumbing,
  whatWeCover: 'Pipes and drains.',
  workerNoun: 'plumbers',
  slug: 'plumbing',
);

void main() {
  group('normalizeNorthAmericanPhone', () {
    test('every common way of writing a number becomes +1XXXXXXXXXX', () {
      for (final raw in [
        '780 555 0100', '(780) 555-0100', '780.555.0100', '780-555-0100', '1-780-555-0100',
        '17805550100', '+1 780 555 0100', '+1 (780) 555-0100', '+17805550100', '  7805550100 ',
      ]) {
        expect(normalizeNorthAmericanPhone(raw), '+17805550100', reason: raw);
      }
    });

    test('eleven digits must start with 1', () {
      expect(normalizeNorthAmericanPhone('58792199587'), isNull);
      expect(normalizeNorthAmericanPhone('15872199587'), '+15872199587');
    });

    test('anything that is not a North American number is rejected', () {
      for (final raw in [
        '', '   ', 'abc', '555 0100', '780555010', '178055501001', '+44 20 7946 0958', '+380 44 123 4567',
        '1234567890', '0805550100', '7801550100', '780-555-CALL', '780 555 0100 ext 5', '++17805550100',
        '780+5550100', '7805550100+', '()-.', '+7805550100',
      ]) {
        expect(normalizeNorthAmericanPhone(raw), isNull, reason: raw);
      }
    });
  });

  group('the request form', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> openConfirmation(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen(initialCategory: _plumbing)));
      await tester.tap(find.text('Today'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next')); // location is prefilled
      await tester.pumpAndSettle();
    }

    ElevatedButton continueButton(WidgetTester tester) =>
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Continue'));

    Future<void> typePhone(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField).first, text);
      await tester.pump();
    }

    testWidgets('an empty field shows no error, but Continue stays off', (tester) async {
      await openConfirmation(tester);
      expect(find.byKey(const Key('phone-error')), findsNothing);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(continueButton(tester).onPressed, isNull);
    });

    testWidgets('an 11-digit number not starting with 1 shows a clear error and blocks Continue', (tester) async {
      await openConfirmation(tester);
      await tester.tap(find.byType(Checkbox)); // consent given, so only the phone is in the way
      await tester.pump();
      await typePhone(tester, '58792199587');

      expect(find.byKey(const Key('phone-error')), findsOneWidget);
      expect(find.text(kInvalidPhoneMessage), findsOneWidget);
      expect(continueButton(tester).onPressed, isNull);
    });

    testWidgets('the error clears and Continue turns on once the number is valid', (tester) async {
      await openConfirmation(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await typePhone(tester, '58792199587');
      expect(find.byKey(const Key('phone-error')), findsOneWidget);

      await typePhone(tester, '(780) 555-0100');
      expect(find.byKey(const Key('phone-error')), findsNothing);
      expect(continueButton(tester).onPressed, isNotNull);

      await typePhone(tester, '+44 20 7946 0958'); // valid number, wrong country
      expect(find.byKey(const Key('phone-error')), findsOneWidget);
      expect(continueButton(tester).onPressed, isNull);

      await typePhone(tester, '');
      expect(find.byKey(const Key('phone-error')), findsNothing);
    });

    testWidgets('the number is sent to the backend as +1XXXXXXXXXX', (tester) async {
      final requests = <http.Request>[];
      await http.runWithClient(() async {
        await openConfirmation(tester);
        await typePhone(tester, '(780) 555-0100');
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(HomeScreen), findsOneWidget);
      }, () => MockClient((request) async {
            requests.add(request);
            if (request.method == 'POST') {
              return http.Response(jsonEncode({'request_id': 1, 'status': 'new'}), 201);
            }
            return http.Response(jsonEncode({'requests': [], 'notifications': []}), 200);
          }));

      final post = requests.firstWhere((r) => r.method == 'POST' && r.url.path.endsWith('/requests/'));
      expect(jsonDecode(post.body), containsPair('phone', '+17805550100'));
    });
  });
}
