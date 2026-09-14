import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:toplinkai_app/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('Onboarding flow walks through all 4 steps', (WidgetTester tester) async {
    // The default test surface (800x600) is far shorter than any real phone
    // screen; use a realistic device size so layout assertions reflect what
    // actually ships instead of an artificially cramped canvas.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Pumps OnboardingScreen directly rather than the full app (TopLinkApp)
    // — the app's real entry point is now gated behind a subscription check
    // (see subscription/app_entry_point.dart), which needs a live backend.
    // This test is about the onboarding step flow itself, not the gate.
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

    // Step 1: category selection — tapping a card opens its detail page,
    // which fetches providers over the network. TestWidgetsFlutterBinding
    // fakes the HttpClient and resolves every request immediately with a 400,
    // so the fetch settles before pumpAndSettle's timeout regardless of
    // whether a real backend is running.
    expect(find.text('What do you need help with?'), findsOneWidget);
    await tester.tap(find.text('Plumbing'));
    await tester.pumpAndSettle();
    expect(find.text('Select this category'), findsOneWidget);
    await tester.tap(find.text('Select this category'));
    await tester.pumpAndSettle();

    // Selecting the category pops back into onboarding and advances straight
    // to the urgency step.
    expect(find.text('How soon do you need this done?'), findsOneWidget);
    await tester.tap(find.text('Today'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 3: location — prefilled with a demo location, so Next is enabled.
    expect(find.text('Where are you located?'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 4: confirmation message.
    expect(
      find.text('We found providers ready to help you in your area'),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
  });
}
