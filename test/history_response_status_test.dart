import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toplinkai_app/api/provider_match.dart';
import 'package:toplinkai_app/home/home_screen.dart';

// Covers the client-side half of the provider-response loop: a request that
// has been accepted or declined by the provider must render distinctly from
// a plain "Requested"/"Responded" status, since ProviderMatchStatus.responded
// alone doesn't say which. See RequestCard/StatusBadge in home_screen.dart —
// made public for exactly this kind of direct widget test, the same pattern
// real_provider_card_test.dart already uses for RealProviderCard.

ProviderMatchRecord _match({
  String status = ProviderMatchStatus.requested,
  String providerDecision = '',
  String providerMessage = '',
}) {
  final now = DateTime(2026, 1, 1);
  return ProviderMatchRecord(
    id: 1,
    category: 'plumbing',
    city: 'Edmonton',
    providerName: 'Acme Plumbing',
    providerPhone: '+1 780-904-1234',
    providerAddress: '1 Main St NW, Edmonton, AB',
    providerWebsite: 'https://acme.example',
    problemDescription: 'Leaky kitchen faucet',
    status: status,
    providerDecision: providerDecision,
    providerMessage: providerMessage,
    respondedAt: providerDecision.isEmpty ? null : now,
    firstUnlockedAt: now,
    lastViewedAt: now,
  );
}

Widget _hostBadge(String status, String decision) => MaterialApp(
      home: Scaffold(body: StatusBadge(status: status, decision: decision)),
    );

Widget _hostCard(ProviderMatchRecord match) => MaterialApp(
      home: Scaffold(
        body: RequestCard(match: match, onStatusSelected: (_) {}),
      ),
    );

void main() {
  group('StatusBadge', () {
    testWidgets('shows the plain status label while still requested', (tester) async {
      await tester.pumpWidget(_hostBadge(ProviderMatchStatus.requested, ''));
      expect(find.text('Requested'), findsOneWidget);
    });

    testWidgets('shows "Accepted" — not the generic "Responded" — once the provider accepts', (tester) async {
      await tester.pumpWidget(_hostBadge(ProviderMatchStatus.responded, ProviderDecision.accepted));
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('Responded'), findsNothing);
    });

    testWidgets('shows "Declined" — not the generic "Responded" — once the provider declines', (tester) async {
      await tester.pumpWidget(_hostBadge(ProviderMatchStatus.responded, ProviderDecision.declined));
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('Responded'), findsNothing);
    });

    testWidgets('still falls back to "Responded" if a row has no decision recorded (legacy data)', (tester) async {
      await tester.pumpWidget(_hostBadge(ProviderMatchStatus.responded, ''));
      expect(find.text('Responded'), findsOneWidget);
    });
  });

  group('RequestCard', () {
    testWidgets('a merely-requested match shows no declined notice and no message', (tester) async {
      await tester.pumpWidget(_hostCard(_match()));
      expect(find.text('This provider declined your request.'), findsNothing);
      expect(find.textContaining('"'), findsNothing);
    });

    testWidgets('an accepted match shows the reply message but not a declined notice', (tester) async {
      await tester.pumpWidget(_hostCard(_match(
        status: ProviderMatchStatus.responded,
        providerDecision: ProviderDecision.accepted,
        providerMessage: 'On our way tomorrow at 9am.',
      )));
      expect(find.text('This provider declined your request.'), findsNothing);
      expect(find.text('"On our way tomorrow at 9am."'), findsOneWidget);
    });

    testWidgets('a declined match is surfaced clearly, not left looking pending', (tester) async {
      await tester.pumpWidget(_hostCard(_match(
        status: ProviderMatchStatus.responded,
        providerDecision: ProviderDecision.declined,
        providerMessage: 'Fully booked this week.',
      )));
      expect(find.text('This provider declined your request.'), findsOneWidget);
      expect(find.text('"Fully booked this week."'), findsOneWidget);
      expect(find.text('Declined'), findsOneWidget);
    });

    testWidgets('the status popup menu still lets the client manually advance status', (tester) async {
      String? selected;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RequestCard(match: _match(), onStatusSelected: (s) => selected = s)),
      ));
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contacted').last);
      await tester.pumpAndSettle();
      expect(selected, ProviderMatchStatus.contacted);
    });
  });
}
