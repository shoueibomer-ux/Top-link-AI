import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:toplinkai_app/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('Onboarding flow walks through all 4 steps', (WidgetTester tester) async {
    // The category detail page now fetches a device id (shared_preferences)
    // before searching providers — without this, SharedPreferences.getInstance()
    // has no plugin implementation to talk to under flutter test and never
    // resolves, so pumpAndSettle times out waiting on the loading spinner.
    SharedPreferences.setMockInitialValues({});

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

    // Step 1: category selection is now a two-level drill-down (Phase 1B).
    // The dynamic catalog fetch also gets the fake 400 from
    // TestWidgetsFlutterBinding, so CategoryStep falls back to the static
    // category list wrapped as a single "All categories" group — tap that,
    // then the leaf category, whose detail page fetches providers the same
    // fake-400 way as before.
    expect(find.text('What do you need help with?'), findsOneWidget);
    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
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
