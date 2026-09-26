import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/subscription/paywall_screen.dart';

Widget _host() => MaterialApp(home: PaywallScreen(onSubscribed: () {}));

void main() {
  setUp(() {
    // getDeviceId() (device_id.dart) needs a plugin implementation to
    // resolve under flutter test — same requirement as the onboarding
    // flow's own test (see widget_test.dart).
    SharedPreferences.setMockInitialValues({});
  });

  // The default test surface (800x600) is far shorter than any real phone
  // screen and cuts off the CTA button below two plan cards — same fix
  // widget_test.dart already uses for the onboarding flow.
  void useRealisticDeviceSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('shows both plans, clearly priced and labeled, with the subscription selected by default',
      (tester) async {
    useRealisticDeviceSize(tester);
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Monthly Plan'), findsOneWidget);
    expect(find.text('\$9.99 / month'), findsOneWidget);

    expect(find.text('One-Time Unlock'), findsOneWidget);
    expect(find.text('\$4.99 one-time'), findsOneWidget);
    expect(find.text('Full contact details for one provider'), findsOneWidget);

    // Subscription is the default selection, so its CTA shows first.
    expect(find.widgetWithText(ElevatedButton, 'Subscribe'), findsOneWidget);
  });

  testWidgets('selecting the one-time plan switches the CTA and price emphasis', (tester) async {
    useRealisticDeviceSize(tester);
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('One-Time Unlock'));
    await tester.pump();

    expect(find.widgetWithText(ElevatedButton, 'Unlock one provider — \$4.99'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Subscribe'), findsNothing);
  });

  testWidgets('switching back to the subscription plan restores its CTA', (tester) async {
    useRealisticDeviceSize(tester);
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('One-Time Unlock'));
    await tester.pump();
    await tester.tap(find.text('Monthly Plan'));
    await tester.pump();

    expect(find.widgetWithText(ElevatedButton, 'Subscribe'), findsOneWidget);
  });

  testWidgets('the one-time plan is not wired to a purchase yet — tapping its CTA is a no-op notice, not a charge',
      (tester) async {
    useRealisticDeviceSize(tester);
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('One-Time Unlock'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Unlock one provider — \$4.99'));
    await tester.pump();

    expect(find.text('One-time unlock purchases are coming soon.'), findsOneWidget);
  });
}
