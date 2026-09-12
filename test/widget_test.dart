import 'package:flutter_test/flutter_test.dart';

import 'package:toplinkai_app/main.dart';

void main() {
  testWidgets('Onboarding flow walks through all 4 steps', (WidgetTester tester) async {
    await tester.pumpWidget(const TopLinkApp());

    // Step 1: category selection — Continue disabled until a category is picked.
    expect(find.text('What do you need help with?'), findsOneWidget);
    await tester.tap(find.text('Plumbing'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2: urgency selection.
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
