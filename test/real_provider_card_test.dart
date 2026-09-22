import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toplinkai_app/api/real_provider.dart';
import 'package:toplinkai_app/widgets/real_provider_card.dart';

const _unlockedProvider = RealProvider(
  name: 'Acme Plumbing',
  phone: '+1 780-555-0100',
  city: 'Edmonton',
  address: '1 Main St NW, Edmonton, AB',
  website: 'https://acme.example',
  mapsUrl: 'https://maps.example/acme',
  rating: 4.8,
  ratingCount: 120,
  placeId: 'place-1',
  isUnlocked: true,
);

const _lockedProvider = RealProvider(
  name: 'Locked Plumbing Co',
  phone: '+1 780-904-XXXX',
  city: 'Edmonton',
  rating: 4.6,
  ratingCount: 80,
  placeId: 'place-2',
);

Widget _host(RealProvider provider, {VoidCallback? onDismiss}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RealProviderCard(provider: provider, category: 'plumbing', onDismiss: onDismiss),
        ),
      ),
    );

void main() {
  testWidgets('shows a trailing chevron that does not overlap the action buttons', (tester) async {
    await tester.pumpWidget(_host(_unlockedProvider));
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down_outlined), findsOneWidget);
    final chevron = tester.getRect(find.byIcon(Icons.chevron_right));
    for (final icon in [Icons.bookmark_border, Icons.thumb_down_outlined]) {
      expect(chevron.overlaps(tester.getRect(find.byIcon(icon))), isFalse);
    }
  });

  testWidgets('an unlocked provider shows its full address and no unlock CTA', (tester) async {
    await tester.pumpWidget(_host(_unlockedProvider));
    expect(find.text('1 Main St NW, Edmonton, AB'), findsOneWidget);
    expect(find.byType(UnlockCtaButton), findsNothing);
  });

  testWidgets('a locked provider shows only the city and an unlock CTA, never the address', (tester) async {
    await tester.pumpWidget(_host(_lockedProvider));
    expect(find.text('Edmonton'), findsOneWidget);
    expect(find.textContaining('Main St'), findsNothing);
    expect(find.byType(UnlockCtaButton), findsOneWidget);
    expect(find.text('Unlock contact — \$4.99'), findsOneWidget);
    expect(find.text('or subscribe for unlimited unlocks'), findsOneWidget);
    // The button label itself must stay short — "or subscribe" belongs on
    // its own subtitle line, not crammed into the pill (see UnlockCtaButton).
    expect(find.textContaining('\$4.99 or subscribe'), findsNothing);
  });

  testWidgets('tapping an unlocked card opens a details sheet with full contact info', (tester) async {
    await tester.pumpWidget(_host(_unlockedProvider));
    await tester.tap(find.text('Acme Plumbing'));
    await tester.pumpAndSettle();
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Website'), findsOneWidget);
    expect(find.text('Google Maps'), findsOneWidget);
  });

  testWidgets('tapping a locked card opens a sheet showing city and an unlock CTA, not address/website', (tester) async {
    await tester.pumpWidget(_host(_lockedProvider));
    await tester.tap(find.text('Locked Plumbing Co'));
    await tester.pumpAndSettle();
    expect(find.text('City'), findsOneWidget);
    expect(find.text('Address'), findsNothing);
    expect(find.text('Website'), findsNothing);
    // One on the card behind the sheet, one inside the sheet itself.
    expect(find.byType(UnlockCtaButton), findsNWidgets(2));
  });

  testWidgets('bookmark and not-interested still work and do not open the sheet', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(_host(_unlockedProvider, onDismiss: () => dismissed = true));

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.text('Address'), findsNothing);

    await tester.tap(find.byIcon(Icons.thumb_down_outlined));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
    expect(find.text('Address'), findsNothing);
  });

  testWidgets('the unlock CTA does not overflow in a narrow chat-bubble width', (tester) async {
    // Regression test: found live in the Ask AI chat flow, where
    // RealProviderCard sits inside a bubble capped at 85% of screen width —
    // narrower than the card's usual full-width home/category-list context.
    // 360 matches that bubble's real width on a typical phone (~85% of a
    // ~412dp-wide screen); this is about reproducing that real constraint,
    // not stress-testing arbitrarily narrow widths no device actually uses.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: RealProviderCard(provider: _lockedProvider, category: 'snow-removal'),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the unlock CTA does not overflow even at an extreme narrow width', (tester) async {
    // Tighter than any real device is likely to give this widget — proves
    // the ellipsis/Flexible safety net, not just the shortened label, holds.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: UnlockCtaButton(onTap: () {}),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the details sheet unlock CTA also uses the short label with no overflow', (tester) async {
    await tester.pumpWidget(_host(_lockedProvider));
    await tester.tap(find.text('Locked Plumbing Co'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock contact — \$4.99'), findsNWidgets(2)); // card + sheet
    expect(find.text('or subscribe for unlimited unlocks'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
