import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toplinkai_app/api/real_provider.dart';
import 'package:toplinkai_app/widgets/real_provider_card.dart';

const _provider = RealProvider(
  name: 'Acme Plumbing',
  phone: '+1 780-555-0100',
  address: '1 Main St NW, Edmonton, AB',
  website: 'https://acme.example',
  mapsUrl: 'https://maps.example/acme',
  rating: 4.8,
  ratingCount: 120,
);

Widget _host({VoidCallback? onDismiss}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RealProviderCard(provider: _provider, onDismiss: onDismiss),
        ),
      ),
    );

void main() {
  testWidgets('shows a trailing chevron that does not overlap the action buttons', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down_outlined), findsOneWidget);
    final chevron = tester.getRect(find.byIcon(Icons.chevron_right));
    for (final icon in [Icons.bookmark_border, Icons.thumb_down_outlined]) {
      expect(chevron.overlaps(tester.getRect(find.byIcon(icon))), isFalse);
    }
  });

  testWidgets('tapping the card opens a details sheet', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('Acme Plumbing'));
    await tester.pumpAndSettle();
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Website'), findsOneWidget);
    expect(find.text('Google Maps'), findsOneWidget);
  });

  testWidgets('bookmark and not-interested still work and do not open the sheet', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(_host(onDismiss: () => dismissed = true));

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.text('Address'), findsNothing);

    await tester.tap(find.byIcon(Icons.thumb_down_outlined));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
    expect(find.text('Address'), findsNothing);
  });
}
