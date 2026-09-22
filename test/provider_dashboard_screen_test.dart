import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toplinkai_app/api/provider_match.dart';
import 'package:toplinkai_app/provider/provider_dashboard_screen.dart';

// Covers the provider-side half of the response loop: IncomingRequestCard
// (public for exactly this — see its doc comment) owns the reply-message
// field and Accept/Decline actions, and is tested directly with a stubbed
// onRespond callback rather than needing to mock the network call the real
// dashboard makes to fetch the queue (ProviderIncomingRequestListView).

ProviderMatchRecord _request({String problemDescription = 'Leaky kitchen faucet'}) {
  final now = DateTime(2026, 1, 1);
  return ProviderMatchRecord(
    id: 7,
    category: 'plumbing',
    city: 'Edmonton',
    providerName: 'Acme Plumbing',
    providerPhone: '+1 780-904-1234',
    providerAddress: '1 Main St NW, Edmonton, AB',
    providerWebsite: 'https://acme.example',
    problemDescription: problemDescription,
    status: ProviderMatchStatus.requested,
    providerDecision: '',
    providerMessage: '',
    respondedAt: null,
    firstUnlockedAt: now,
    lastViewedAt: now,
  );
}

Widget _host(ProviderMatchRecord request, Future<void> Function(String, String) onRespond) => MaterialApp(
      home: Scaffold(body: IncomingRequestCard(request: request, onRespond: onRespond)),
    );

void main() {
  testWidgets('shows the category, city, and job description', (tester) async {
    await tester.pumpWidget(_host(_request(), (_, _) async {}));
    expect(find.text('Plumbing'), findsOneWidget);
    expect(find.text('Edmonton'), findsOneWidget);
    expect(find.text('Leaky kitchen faucet'), findsOneWidget);
  });

  testWidgets('tapping Accept calls onRespond with "accepted" and no message when the field is left blank',
      (tester) async {
    String? gotDecision;
    String? gotMessage;
    await tester.pumpWidget(_host(_request(), (decision, message) async {
      gotDecision = decision;
      gotMessage = message;
    }));

    // Not pumpAndSettle: a successful respond leaves IncomingRequestCard's
    // own "responding" spinner running forever by design (see its class
    // doc — the real dashboard removes the card from the tree instead of
    // this widget ever resetting itself), so settling would time out here
    // with no parent around to do that removal.
    await tester.tap(find.text('Accept'));
    await tester.pump();

    expect(gotDecision, ProviderDecision.accepted);
    expect(gotMessage, '');
  });

  testWidgets('typing a reply and tapping Accept passes the trimmed message through', (tester) async {
    String? gotMessage;
    await tester.pumpWidget(_host(_request(), (_, message) async {
      gotMessage = message;
    }));

    await tester.enterText(find.byType(TextField), '  On our way tomorrow at 9am.  ');
    await tester.tap(find.text('Accept'));
    await tester.pump();

    expect(gotMessage, 'On our way tomorrow at 9am.');
  });

  testWidgets('tapping Decline calls onRespond with "declined"', (tester) async {
    String? gotDecision;
    await tester.pumpWidget(_host(_request(), (decision, _) async {
      gotDecision = decision;
    }));

    await tester.tap(find.text('Decline'));
    await tester.pump();

    expect(gotDecision, ProviderDecision.declined);
  });

  testWidgets('both actions are disabled while a response is in flight', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(_host(_request(), (_, _) => completer.future));

    await tester.tap(find.text('Accept'));
    await tester.pump();

    final acceptButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    final declineButton = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(acceptButton.onPressed, isNull);
    expect(declineButton.onPressed, isNull);

    completer.complete();
    await tester.pump();
  });
}
