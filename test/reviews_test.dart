import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/provider_profile.dart';
import 'package:toplinkai_app/api/reviews.dart';
import 'package:toplinkai_app/api/service_request.dart';
import 'package:toplinkai_app/home/home_screen.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';
import 'package:toplinkai_app/provider/provider_leads_tab.dart';
import 'package:toplinkai_app/provider/provider_session.dart';
import 'package:toplinkai_app/reviews/favorites_screen.dart';
import 'package:toplinkai_app/reviews/provider_public_screen.dart';
import 'package:toplinkai_app/reviews/provider_reviews_section.dart';
import 'package:toplinkai_app/widgets/app_drawer.dart';
import 'package:toplinkai_app/widgets/stars.dart';

// Reviews and favorites: rating models, History (rate / edit), a provider's public page, the Favorites list,
// the provider's reviews with their one public reply, and reporting a review.

Map<String, dynamic> reviewJson(
  int id, {
  int rating = 5,
  String comment = 'Fixed it fast',
  String name = 'Pat P.',
  bool mine = false,
  bool hidden = false,
  bool canEdit = false,
  Map<String, dynamic>? reply,
}) => {
  'id': id,
  'rating': rating,
  'comment': comment,
  'client_name': name,
  'created_at': '2026-10-12T12:00:00Z',
  'edited': false,
  'reply': reply,
  'mine': mine,
  'hidden': hidden,
  if (mine) 'can_edit': canEdit,
};

Map<String, dynamic> providerJson({double? average = 4.5, int count = 2}) => {
  'id': 5,
  'business_name': 'Ace Plumbing',
  'bio': 'Family run since 1998.',
  'categories': ['plumbing'],
  'cities': ['Edmonton'],
  'rating_average': average,
  'review_count': count,
};

/// A fake server for the reviews endpoints. It records every request.
class Backend {
  Map<String, dynamic>? myReview;
  bool completed = true;
  bool favorite = false;
  bool failFavorite = false;
  List<Map<String, dynamic>> providerReviews = [
    reviewJson(1, rating: 5, comment: 'Great job', name: 'Sam S.'),
    reviewJson(2, rating: 4, comment: 'On time', name: 'Pat P.', mine: true, canEdit: true),
  ];
  List<Map<String, dynamic>> favorites = [];
  List<Map<String, dynamic>> myProviderReviews = [];
  final requests = <http.Request>[];

  Iterable<http.Request> to(String part, {String? method}) => requests.where(
    (r) => r.url.path.contains(part) && (method == null || r.method == method),
  );

  http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

  Map<String, dynamic> get offer => {
    'offer_id': 42,
    'provider': providerJson(),
    'hired': completed,
    'job_completed': completed,
    'can_complete': !completed,
    'review': myReview,
    'can_review': completed && myReview == null,
  };

  http.Client get client => MockClient(handle);

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
    if (path.endsWith('/requests/mine/')) {
      return json({
        'requests': [
          {
            'id': 7,
            'category': 'plumbing',
            'city': 'Edmonton',
            'problem_description': 'Leaking tap',
            'phone': '+17805550100',
            'status': 'new',
            'created_at': '2026-10-10T12:00:00Z',
            'accepted_offers': [offer],
          },
        ],
      });
    }
    if (path.endsWith('/conversations/')) return json({'conversations': [], 'total_unread': 0});
    if (path.endsWith('/offers/42/review/')) {
      if (request.method == 'POST') {
        myReview = reviewJson(9, rating: body['rating'] as int, comment: body['comment'] as String, mine: true, canEdit: true);
        return json(myReview!, 201);
      }
      if (request.method == 'PATCH') {
        myReview = reviewJson(9, rating: body['rating'] as int, comment: body['comment'] as String, mine: true, canEdit: true);
        return json(myReview!);
      }
    }
    if (path.endsWith('/providers/5/reviews/')) {
      return json({'provider': providerJson(), 'reviews': providerReviews, 'is_favorite': favorite});
    }
    if (path.endsWith('/favorites/5/')) {
      if (failFavorite) return json({'detail': 'Provider not found.'}, 404);
      favorite = request.method == 'PUT';
      return json({'is_favorite': favorite});
    }
    if (path.endsWith('/favorites/')) return json({'favorites': favorites});
    if (path.endsWith('/provider/reviews/')) {
      return json({
        'summary': {'rating_average': 4.0, 'review_count': myProviderReviews.length},
        'reviews': myProviderReviews,
      });
    }
    final reply = RegExp(r'/reviews/(\d+)/reply/$').firstMatch(path);
    if (reply != null) {
      final id = int.parse(reply.group(1)!);
      final updated = {
        ...myProviderReviews.firstWhere((r) => r['id'] == id),
        'reply': {'text': body['text'], 'created_at': '2026-10-13T12:00:00Z'},
      };
      myProviderReviews = [for (final r in myProviderReviews) r['id'] == id ? updated : r];
      return json(updated, 201);
    }
    if (RegExp(r'/reviews/\d+/report/$').hasMatch(path)) return json({'reported': true}, 201);
    return json({'detail': 'unexpected ${request.method} $path'}, 404);
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> inApp(WidgetTester tester, Backend backend, Future<void> Function() body) {
  return http.runWithClient(body, () => backend.client);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthStorage.save(access: 'tok-1', refresh: 'ref-1');
  });

  // -------------------------------------------------------------------------------------------------
  group('rating models', () {
    test('an offer carries the provider rating, the review and whether it can be reviewed', () {
      final offer = AcceptedOffer.fromJson({
        'offer_id': 1,
        'provider': providerJson(),
        'job_completed': true,
        'review': reviewJson(3, rating: 4, mine: true, canEdit: true),
        'can_review': false,
      });
      expect(offer.providerRating.average, 4.5);
      expect(offer.providerRating.count, 2);
      expect(offer.review!.rating, 4);
      expect(offer.review!.mine, isTrue);
      expect(offer.review!.canEdit, isTrue);
      expect(offer.canReview, isFalse);
    });

    test('an older response without ratings still parses', () {
      final offer = AcceptedOffer.fromJson({
        'offer_id': 1,
        'provider': {'id': 5, 'business_name': 'Ace'},
      });
      expect(offer.providerRating.hasReviews, isFalse);
      expect(offer.review, isNull);
      expect(offer.canReview, isFalse);
    });

    test('a review keeps the shortened name and the provider reply', () {
      final review = Review.fromJson(reviewJson(1, reply: {'text': 'Thanks!', 'created_at': '2026-10-13T12:00:00Z'}));
      expect(review.clientName, 'Pat P.');
      expect(review.reply!.text, 'Thanks!');
      expect(review.mine, isFalse);
    });

    test('a provider profile reads its own rating', () {
      final profile = ProviderProfileData.fromJson({
        'business_name': 'Ace',
        'rating_average': 3.5,
        'review_count': 4,
      });
      expect(profile.rating.average, 3.5);
      expect(profile.rating.count, 4);
    });

    test('no reviews means no average', () {
      final none = RatingSummary.fromJson({'rating_average': null, 'review_count': 0});
      expect(none.average, isNull);
      expect(none.hasReviews, isFalse);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('rating widgets', () {
    testWidgets('RatingLine shows the average and a pluralised count', (tester) async {
      Future<void> show(RatingSummary r) => tester.pumpWidget(MaterialApp(home: Scaffold(body: RatingLine(rating: r))));
      await show(const RatingSummary(average: 4.5, count: 12));
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('(12 reviews)'), findsOneWidget);
      await show(const RatingSummary(average: 5.0, count: 1));
      expect(find.text('(1 review)'), findsOneWidget);
      await show(const RatingSummary());
      expect(find.text('No reviews yet'), findsOneWidget);
    });

    testWidgets('StarPicker reports the star that was tapped', (tester) async {
      var value = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => StarPicker(value: value, onChanged: (v) => setState(() => value = v)),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('star-4')));
      await tester.pump();
      expect(value, 4);
      expect(find.text('Very good'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('History', () {
    testWidgets('shows the provider rating on the card', (tester) async {
      bigScreen(tester);
      final backend = Backend()..completed = false;
      await inApp(tester, backend, () async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoryTab())));
        await settle(tester);
        expect(find.descendant(of: find.byKey(const Key('rating-42')), matching: find.text('4.5')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('rating-42')), matching: find.text('(2 reviews)')), findsOneWidget);
        expect(find.byKey(const Key('rate-42')), findsNothing, reason: 'the job is not complete yet');
      });
    });

    testWidgets('a completed job can be rated: stars are required, the comment is optional', (tester) async {
      bigScreen(tester);
      final backend = Backend();
      await inApp(tester, backend, () async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoryTab())));
        await settle(tester);
        await tester.tap(find.byKey(const Key('rate-42')));
        await settle(tester);
        expect(find.text('Rate Ace Plumbing'), findsOneWidget);

        await tester.tap(find.byKey(const Key('review-save')));
        await settle(tester);
        expect(find.text('Tap a star to choose your rating.'), findsOneWidget);
        expect(backend.to('/review/', method: 'POST'), isEmpty);

        await tester.tap(find.byKey(const Key('star-4')));
        await tester.enterText(find.byKey(const Key('review-comment')), '  Quick and tidy  ');
        await tester.pump();
        await tester.tap(find.byKey(const Key('review-save')));
        await settle(tester);

        final post = backend.to('/offers/42/review/', method: 'POST').single;
        expect(jsonDecode(post.body), {'rating': 4, 'comment': 'Quick and tidy'});
        expect(post.headers['Authorization'], 'Bearer tok-1');
        expect(find.text('Thanks for your review.'), findsOneWidget);
        // History reloads and now shows the review with an Edit button instead of Rate.
        expect(find.byKey(const Key('rate-42')), findsNothing);
        expect(find.byKey(const Key('my-review-42')), findsOneWidget);
        expect(find.byKey(const Key('edit-review-42')), findsOneWidget);
      });
    });

    testWidgets('a server refusal is shown in the sheet and keeps it open', (tester) async {
      bigScreen(tester);
      final backend = Backend();
      final failing = MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/review/')) {
          return http.Response(jsonEncode({'detail': 'You have already reviewed this job.'}), 409);
        }
        return backend.handle(request);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoryTab())));
        await settle(tester);
        await tester.tap(find.byKey(const Key('rate-42')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('star-5')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('review-save')));
        await settle(tester);
        expect(find.text('You have already reviewed this job.'), findsOneWidget);
        expect(find.byKey(const Key('review-save')), findsOneWidget);
      }, () => failing);
    });

    testWidgets('an existing review can be edited while the window is open', (tester) async {
      bigScreen(tester);
      final backend = Backend()..myReview = reviewJson(9, rating: 2, comment: 'Late', mine: true, canEdit: true);
      await inApp(tester, backend, () async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoryTab())));
        await settle(tester);
        expect(find.byKey(const Key('rate-42')), findsNothing, reason: 'already reviewed');
        await tester.tap(find.byKey(const Key('edit-review-42')));
        await settle(tester);
        expect(find.text('Edit your review'), findsOneWidget);
        expect(find.text('Late'), findsOneWidget);
        await tester.tap(find.byKey(const Key('star-5')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('review-save')));
        await settle(tester);
        final patch = backend.to('/offers/42/review/', method: 'PATCH').single;
        expect(jsonDecode(patch.body), {'rating': 5, 'comment': 'Late'});
        expect(find.text('Your review was updated.'), findsOneWidget);
      });
    });

    testWidgets('after 7 days there is no Edit button', (tester) async {
      bigScreen(tester);
      final backend = Backend()..myReview = reviewJson(9, mine: true, canEdit: false);
      await inApp(tester, backend, () async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoryTab())));
        await settle(tester);
        expect(find.byKey(const Key('my-review-42')), findsOneWidget);
        expect(find.byKey(const Key('edit-review-42')), findsNothing);
        expect(find.byKey(const Key('rate-42')), findsNothing);
      });
    });

    testWidgets('a review removed by a moderator says so', (tester) async {
      bigScreen(tester);
      final backend = Backend()..myReview = reviewJson(9, mine: true, hidden: true, canEdit: false);
      await inApp(tester, backend, () async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoryTab())));
        await settle(tester);
        expect(find.text('Removed by Tabmatch'), findsOneWidget);
        expect(find.byKey(const Key('edit-review-42')), findsNothing);
      });
    });

    testWidgets('tapping the provider opens their page', (tester) async {
      bigScreen(tester);
      final backend = Backend();
      await inApp(tester, backend, () async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistoryTab())));
        await settle(tester);
        await tester.tap(find.byKey(const Key('provider-42')));
        await settle(tester);
        expect(backend.to('/providers/5/reviews/'), isNotEmpty);
        expect(find.text('Family run since 1998.'), findsOneWidget);
      });
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('a provider\'s public page', () {
    Widget page() => MaterialApp(home: ProviderPublicScreen(session: AuthSession(), providerId: 5));

    testWidgets('shows the rating, details and every review with the shortened client name', (tester) async {
      bigScreen(tester);
      final backend = Backend();
      backend.providerReviews[0] = reviewJson(1, comment: 'Great job', name: 'Sam S.', reply: {'text': 'Thanks Sam!', 'created_at': '2026-10-13T12:00:00Z'});
      await inApp(tester, backend, () async {
        await tester.pumpWidget(page());
        await settle(tester);
        expect(find.text('Ace Plumbing'), findsWidgets);
        expect(find.descendant(of: find.byKey(const Key('provider-rating')), matching: find.text('4.5')), findsOneWidget);
        expect(find.text('Edmonton'), findsOneWidget);
        expect(find.byKey(const Key('review-name-1')), findsOneWidget);
        expect(find.text('Sam S.'), findsOneWidget);
        expect(find.text('Great job'), findsOneWidget);
        expect(find.text('Thanks Sam!'), findsOneWidget);
        expect(find.text('Pat P.'), findsOneWidget);
      });
    });

    testWidgets('says so when there are no reviews', (tester) async {
      bigScreen(tester);
      final backend = Backend()..providerReviews = [];
      await inApp(tester, backend, () async {
        await tester.pumpWidget(page());
        await settle(tester);
        expect(find.byKey(const Key('no-reviews')), findsOneWidget);
      });
    });

    testWidgets('the heart saves and removes the provider', (tester) async {
      bigScreen(tester);
      final backend = Backend();
      await inApp(tester, backend, () async {
        await tester.pumpWidget(page());
        await settle(tester);
        expect(find.byIcon(Icons.favorite_border), findsOneWidget);
        await tester.tap(find.byKey(const Key('favorite-toggle')));
        await settle(tester);
        expect(find.byIcon(Icons.favorite), findsOneWidget);
        expect(backend.to('/favorites/5/', method: 'PUT'), hasLength(1));
        await tester.tap(find.byKey(const Key('favorite-toggle')));
        await settle(tester);
        expect(find.byIcon(Icons.favorite_border), findsOneWidget);
        expect(backend.to('/favorites/5/', method: 'DELETE'), hasLength(1));
      });
    });

    testWidgets('the heart goes back if the server refuses', (tester) async {
      bigScreen(tester);
      final backend = Backend()..failFavorite = true;
      await inApp(tester, backend, () async {
        await tester.pumpWidget(page());
        await settle(tester);
        await tester.tap(find.byKey(const Key('favorite-toggle')));
        await settle(tester);
        expect(find.byIcon(Icons.favorite_border), findsOneWidget);
        expect(find.text('Provider not found.'), findsOneWidget);
      });
    });

    testWidgets('a review can be reported, but your own cannot', (tester) async {
      bigScreen(tester);
      final backend = Backend();
      await inApp(tester, backend, () async {
        await tester.pumpWidget(page());
        await settle(tester);
        expect(find.byKey(const Key('report-review-2')), findsNothing, reason: 'review 2 is mine');
        await tester.tap(find.byKey(const Key('report-review-1')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('report-reason-fake')));
        await settle(tester);
        final report = backend.to('/reviews/1/report/', method: 'POST').single;
        expect(jsonDecode(report.body), {'reason': 'fake'});
        expect(find.text('Thanks. We will take a look at this review.'), findsOneWidget);
      });
    });

    testWidgets('backing out of the report dialog sends nothing', (tester) async {
      bigScreen(tester);
      final backend = Backend();
      await inApp(tester, backend, () async {
        await tester.pumpWidget(page());
        await settle(tester);
        await tester.tap(find.byKey(const Key('report-review-1')));
        await settle(tester);
        await tester.tapAt(const Offset(5, 5)); // outside the dialog
        await settle(tester);
        expect(backend.to('/report/'), isEmpty);
      });
    });

    testWidgets('shows an error with a retry when the page cannot load', (tester) async {
      bigScreen(tester);
      var up = false;
      final backend = Backend();
      await http.runWithClient(() async {
        await tester.pumpWidget(page());
        await settle(tester);
        expect(find.byKey(const Key('provider-page-message')), findsOneWidget);
        up = true;
        await tester.tap(find.byKey(const Key('provider-page-retry')));
        await settle(tester);
        expect(find.text('Family run since 1998.'), findsOneWidget);
      }, () => MockClient((request) async {
            if (!up) return http.Response('{}', 500);
            return backend.handle(request);
          }));
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('Favorites', () {
    testWidgets('lists saved providers with their rating', (tester) async {
      bigScreen(tester);
      final backend = Backend()..favorites = [providerJson()];
      await inApp(tester, backend, () async {
        await tester.pumpWidget(const MaterialApp(home: FavoritesScreen()));
        await settle(tester);
        expect(find.text('Ace Plumbing'), findsOneWidget);
        expect(find.text('(2 reviews)'), findsOneWidget);
      });
    });

    testWidgets('an empty list explains how to add one', (tester) async {
      bigScreen(tester);
      final backend = Backend();
      await inApp(tester, backend, () async {
        await tester.pumpWidget(const MaterialApp(home: FavoritesScreen()));
        await settle(tester);
        expect(find.textContaining('No favorites yet'), findsOneWidget);
      });
    });

    testWidgets('tapping a favorite opens their page, and removing the heart drops them from the list', (tester) async {
      bigScreen(tester);
      final backend = Backend()
        ..favorites = [providerJson()]
        ..favorite = true;
      await inApp(tester, backend, () async {
        await tester.pumpWidget(const MaterialApp(home: FavoritesScreen()));
        await settle(tester);
        await tester.tap(find.byKey(const Key('favorite-5')));
        await settle(tester);
        expect(find.byIcon(Icons.favorite), findsWidgets);
        backend.favorites = []; // what the server will answer once the heart is removed
        await tester.tap(find.byKey(const Key('favorite-toggle')));
        await settle(tester);
        expect(backend.to('/favorites/5/', method: 'DELETE'), hasLength(1));
        await tester.pageBack();
        await settle(tester);
        expect(find.textContaining('No favorites yet'), findsOneWidget);
      });
    });

    testWidgets('signed-out people are asked to sign in', (tester) async {
      bigScreen(tester);
      await AuthStorage.clear();
      await inApp(tester, Backend(), () async {
        await tester.pumpWidget(const MaterialApp(home: FavoritesScreen()));
        await settle(tester);
        expect(find.textContaining('Sign in to see your favorites'), findsOneWidget);
      });
    });

    testWidgets('the client menu has a Favorites item that opens the list', (tester) async {
      bigScreen(tester);
      final backend = Backend();
      await inApp(tester, backend, () async {
        final key = GlobalKey<ScaffoldState>();
        await tester.pumpWidget(MaterialApp(home: Scaffold(key: key, drawer: const AppDrawer(), body: const SizedBox())));
        key.currentState!.openDrawer();
        await settle(tester);
        await tester.tap(find.text('Favorites'));
        await settle(tester);
        expect(find.text('Favorites'), findsOneWidget); // now the screen title
        expect(backend.to('/favorites/'), isNotEmpty);
      });
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('the provider\'s own reviews', () {
    Widget section() => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ProviderReviewsSection(session: AuthSession()))),
    );

    testWidgets('each review without a reply has a Reply button; a replied one shows the reply', (tester) async {
      bigScreen(tester);
      final backend = Backend()
        ..myProviderReviews = [
          reviewJson(1, comment: 'Great job', name: 'Sam S.'),
          reviewJson(2, comment: 'Late but fine', name: 'Pat P.', rating: 3, reply: {'text': 'Sorry about that', 'created_at': '2026-10-13T12:00:00Z'}),
        ];
      await inApp(tester, backend, () async {
        await tester.pumpWidget(section());
        await settle(tester);
        expect(find.byKey(const Key('reply-button-1')), findsOneWidget);
        expect(find.byKey(const Key('reply-button-2')), findsNothing, reason: 'one reply per review');
        expect(find.text('Sorry about that'), findsOneWidget);
        expect(find.byKey(const Key('report-review-1')), findsNothing);
      });
    });

    testWidgets('posting a reply sends it once and shows it', (tester) async {
      bigScreen(tester);
      final backend = Backend()..myProviderReviews = [reviewJson(1, comment: 'Great job', name: 'Sam S.')];
      await inApp(tester, backend, () async {
        await tester.pumpWidget(section());
        await settle(tester);
        await tester.tap(find.byKey(const Key('reply-button-1')));
        await settle(tester);
        expect(find.text('Reply to Sam S.'), findsOneWidget);

        await tester.tap(find.byKey(const Key('reply-send')));
        await settle(tester);
        expect(find.text('Write your reply first.'), findsOneWidget);
        expect(backend.to('/reply/'), isEmpty);

        await tester.enterText(find.byKey(const Key('reply-text')), '  Thank you Sam!  ');
        await tester.pump();
        await tester.tap(find.byKey(const Key('reply-send')));
        await settle(tester);
        final post = backend.to('/reviews/1/reply/', method: 'POST').single;
        expect(jsonDecode(post.body), {'text': 'Thank you Sam!'});
        expect(find.text('Thank you Sam!'), findsOneWidget);
        expect(find.byKey(const Key('reply-button-1')), findsNothing);
      });
    });

    testWidgets('with no reviews yet it says when they can expect one', (tester) async {
      bigScreen(tester);
      await inApp(tester, Backend(), () async {
        await tester.pumpWidget(section());
        await settle(tester);
        expect(find.byKey(const Key('my-reviews-empty')), findsOneWidget);
      });
    });

    testWidgets('the Leads tab shows the provider\'s rating once they have one', (tester) async {
      bigScreen(tester);
      final backend = Backend();
      Future<void> pump(RatingSummary rating) => tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProviderLeadsTab(session: AuthSession(), onSessionExpired: () {}, rating: rating)),
      ));
      await http.runWithClient(() async {
        await pump(const RatingSummary(average: 4.5, count: 3));
        await settle(tester);
        expect(find.byKey(const Key('leads-rating')), findsOneWidget);
        expect(find.text('(3 reviews)'), findsOneWidget);
        await pump(const RatingSummary());
        await settle(tester);
        expect(find.byKey(const Key('leads-rating')), findsNothing);
      }, () => MockClient((request) async => http.Response(jsonEncode({'leads': []}), 200)));
      expect(backend.requests, isEmpty);
    });
  });
}
