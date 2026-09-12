import 'package:flutter_test/flutter_test.dart';

import 'package:toplinkai_app/main.dart';

void main() {
  testWidgets('Onboarding flow walks through all 3 steps', (WidgetTester tester) async {
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

    // Step 3: confirmation message.
    expect(
      find.text('We found providers ready to help you in your area'),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
  });
}
