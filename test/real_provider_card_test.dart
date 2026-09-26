import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/provider_reaction.dart';
import 'package:toplinkai_app/api/real_provider.dart';
import 'package:toplinkai_app/app_colors.dart';
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

Widget _host(RealProvider provider) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RealProviderCard(provider: provider, category: 'plumbing'),
        ),
      ),
    );

/// The card's opacity wrapper around its body: 0.5 while marked not interested.
double _bodyOpacity(WidgetTester tester) => tester
    .widgetList<Opacity>(find.descendant(of: find.byType(RealProviderCard), matching: find.byType(Opacity)))
    .first
    .opacity;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows a trailing chevron that does not overlap the action buttons', (tester) async {
    await tester.pumpWidget(_host(_unlockedProvider));
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down_outlined), findsOneWidget);
    final chevron = tester.getRect(find.byIcon(Icons.chevron_right));
    for (final icon in [Icons.bookmark_border, Icons.thumb_up_outlined, Icons.thumb_down_outlined]) {
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

  group('bookmark / like / not interested', () {
    testWidgets('the three actions sit in a row, in that order, without overlapping', (tester) async {
      await tester.pumpWidget(_host(_unlockedProvider));
      final rects = [Icons.bookmark_border, Icons.thumb_up_outlined, Icons.thumb_down_outlined]
          .map((i) => tester.getRect(find.byIcon(i)))
          .toList();
      expect(rects[0].right, lessThan(rects[1].left));
      expect(rects[1].right, lessThan(rects[2].left));
      expect(rects[0].center.dy, rects[2].center.dy);
    });

    testWidgets('tapping like fills and highlights it, and does not open the sheet', (tester) async {
      await tester.pumpWidget(_host(_unlockedProvider));
      await tester.tap(find.byIcon(Icons.thumb_up_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
      expect(tester.widget<Icon>(find.byIcon(Icons.thumb_up)).color, AppColors.turquoise);
      expect(find.text('Address'), findsNothing); // sheet didn't open
      expect(_bodyOpacity(tester), 1);
    });

    testWidgets('tapping like again un-likes', (tester) async {
      await tester.pumpWidget(_host(_unlockedProvider));
      await tester.tap(find.byIcon(Icons.thumb_up_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.thumb_up));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    });

    testWidgets('not interested fills the icon and dims the card, which stays in place', (tester) async {
      await tester.pumpWidget(_host(_unlockedProvider));
      await tester.tap(find.byIcon(Icons.thumb_down_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.thumb_down), findsOneWidget);
      expect(find.text('Acme Plumbing'), findsOneWidget); // not removed
      expect(_bodyOpacity(tester), lessThan(1));
      expect(find.text('Address'), findsNothing);
    });

    testWidgets('liking a disliked card clears the dislike', (tester) async {
      await tester.pumpWidget(_host(_unlockedProvider));
      await tester.tap(find.byIcon(Icons.thumb_down_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.thumb_up_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
      expect(find.byIcon(Icons.thumb_down), findsNothing);
      expect(find.byIcon(Icons.thumb_down_outlined), findsOneWidget);
      expect(_bodyOpacity(tester), 1);
    });

    testWidgets('disliking a liked card clears the like', (tester) async {
      await tester.pumpWidget(_host(_unlockedProvider));
      await tester.tap(find.byIcon(Icons.thumb_up_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.thumb_down_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.thumb_down), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up), findsNothing);
      expect(_bodyOpacity(tester), lessThan(1));
    });

    testWidgets('the bookmark is independent of like and dislike', (tester) async {
      await tester.pumpWidget(_host(_unlockedProvider));
      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.thumb_up_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.thumb_down_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark), findsOneWidget); // still saved
      expect(find.byIcon(Icons.thumb_down), findsOneWidget);
    });

    testWidgets('reactions are remembered: a fresh card for the same provider shows them', (tester) async {
      await tester.pumpWidget(_host(_unlockedProvider));
      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.thumb_up_outlined));
      await tester.pumpAndSettle();

      // Tear the card down and build a new one — what a relaunch does.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(_unlockedProvider));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
    });

    testWidgets('a reaction belongs to one provider and does not leak to another', (tester) async {
      await tester.pumpWidget(_host(_unlockedProvider));
      await tester.tap(find.byIcon(Icons.thumb_down_outlined));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(_lockedProvider));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.thumb_down), findsNothing);
      expect(_bodyOpacity(tester), 1);
    });

    testWidgets('a tap before the stored reaction has loaded is not overwritten by it', (tester) async {
      SharedPreferences.setMockInitialValues({
        'provider_reactions_disliked': ['place-1'],
      });
      await tester.pumpWidget(_host(_unlockedProvider));
      // Tap like in the very first frame, before the async load resolves.
      await tester.tap(find.byIcon(Icons.thumb_up_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
      expect(find.byIcon(Icons.thumb_down), findsNothing);
    });

    testWidgets('the action row fits a small phone (320dp) with room to spare', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // A bare provider (name only): the test font is far wider than a real
      // one, so a fully populated body can overflow at 320dp for reasons that
      // have nothing to do with the action row this test is about. The action
      // buttons are fixed-size icons, so text scale doesn't affect them.
      const bare = RealProvider(name: 'Acme', phone: '', placeId: 'place-3', isUnlocked: true);
      await tester.pumpWidget(
        MaterialApp(
          home: const Scaffold(body: RealProviderCard(provider: bare, category: 'plumbing')),
        ),
      );
      await tester.tap(find.byIcon(Icons.thumb_up_outlined));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(RealProviderCard));
      final first = tester.getRect(find.byIcon(Icons.bookmark_border));
      final last = tester.getRect(find.byIcon(Icons.thumb_down_outlined));
      // The three buttons take ~112dp of a ~290dp-wide card.
      expect(last.right, lessThanOrEqualTo(card.right));
      expect(first.left, greaterThan(card.left + 100));
    });
  });

  group('ProviderReaction', () {
    test('like clears a dislike, and dislike clears a like', () {
      final disliked = ProviderReaction.none.toggleDisliked();
      expect(disliked.toggleLiked(), const ProviderReaction(liked: true));
      expect(ProviderReaction.none.toggleLiked().toggleDisliked(), const ProviderReaction(disliked: true));
    });

    test('like and dislike are never both set, whatever the tap sequence', () {
      final taps = <ProviderReaction Function(ProviderReaction)>[
        (x) => x.toggleLiked(),
        (x) => x.toggleDisliked(),
        (x) => x.toggleSaved(),
      ];
      // Every 5-tap sequence over the three actions (3^5 = 243).
      for (var n = 0; n < 243; n++) {
        var r = ProviderReaction.none;
        var code = n;
        for (var step = 0; step < 5; step++) {
          r = taps[code % 3](r);
          code ~/= 3;
          expect(r.liked && r.disliked, isFalse, reason: 'sequence $n step $step gave $r');
        }
      }
    });

    test('toggling the bookmark leaves like/dislike alone and vice versa', () {
      expect(const ProviderReaction(liked: true).toggleSaved(), const ProviderReaction(saved: true, liked: true));
      expect(const ProviderReaction(saved: true).toggleLiked(), const ProviderReaction(saved: true, liked: true));
      expect(const ProviderReaction(saved: true).toggleDisliked(), const ProviderReaction(saved: true, disliked: true));
    });
  });

  group('ProviderReactionStore', () {
    test('round-trips a reaction by place id', () async {
      await ProviderReactionStore.save('a', const ProviderReaction(saved: true, liked: true));
      await ProviderReactionStore.save('b', const ProviderReaction(disliked: true));

      expect(await ProviderReactionStore.load('a'), const ProviderReaction(saved: true, liked: true));
      expect(await ProviderReactionStore.load('b'), const ProviderReaction(disliked: true));
      expect(await ProviderReactionStore.load('c'), ProviderReaction.none);
    });

    test('clearing a reaction removes it, and changing one provider leaves the others', () async {
      await ProviderReactionStore.save('a', const ProviderReaction(liked: true));
      await ProviderReactionStore.save('b', const ProviderReaction(liked: true));
      await ProviderReactionStore.save('a', ProviderReaction.none);

      expect(await ProviderReactionStore.load('a'), ProviderReaction.none);
      expect(await ProviderReactionStore.load('b'), const ProviderReaction(liked: true));
    });

    test('flipping like to dislike leaves it stored as only a dislike', () async {
      await ProviderReactionStore.save('a', const ProviderReaction(liked: true));
      await ProviderReactionStore.save('a', const ProviderReaction(disliked: true));
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getStringList('provider_reactions_liked'), isEmpty);
      expect(prefs.getStringList('provider_reactions_disliked'), ['a']);
    });

    test('damaged storage claiming both like and dislike resolves to like', () async {
      SharedPreferences.setMockInitialValues({
        'provider_reactions_liked': ['a'],
        'provider_reactions_disliked': ['a'],
      });
      expect(await ProviderReactionStore.load('a'), const ProviderReaction(liked: true));
    });

    test('a provider with no place id loads as none and saving is a no-op', () async {
      await ProviderReactionStore.save(null, const ProviderReaction(liked: true));
      expect(await ProviderReactionStore.load(null), ProviderReaction.none);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });
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
