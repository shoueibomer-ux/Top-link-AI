import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/api_client.dart';
import 'package:toplinkai_app/api/category_suggestions.dart';
import 'package:toplinkai_app/api/service_request.dart';
import 'package:toplinkai_app/chat/chat_screen.dart';
import 'package:toplinkai_app/home/home_screen.dart';
import 'package:toplinkai_app/onboarding/category_detail_page.dart';
import 'package:toplinkai_app/onboarding/confirmation_step.dart';
import 'package:toplinkai_app/onboarding/onboarding_screen.dart';
import 'package:toplinkai_app/onboarding/service_category.dart';
import 'package:toplinkai_app/onboarding/service_list_page.dart';
import 'package:toplinkai_app/widgets/category_search_view.dart';
import 'package:toplinkai_app/widgets/pressable.dart';

// The full sectors view: every active service is visible, unlaunched ones carry
// a "Coming soon" badge, and a request for one goes on a waitlist.

const _plumbing = ServiceCategory(
  label: 'Plumbing',
  icon: Icons.plumbing,
  whatWeCover: 'Pipes and drains.',
  workerNoun: 'plumbers',
  slug: 'plumbing',
);
const _lawn = ServiceCategory(
  label: 'Lawn Care',
  icon: Icons.grass,
  whatWeCover: 'Mowing and edging.',
  workerNoun: 'lawn care specialists',
  slug: 'lawn-care',
  isLaunched: false,
);

final _catalogJson = [
  {
    'id': 1,
    'name': 'Trades',
    'slug': 'trades',
    'icon_name': 'construction',
    'services': [
      {
        'id': 1, 'name': 'Plumbing', 'slug': 'plumbing', 'icon_name': 'plumbing',
        'what_we_cover': 'Pipes and drains.', 'worker_noun': 'plumbers', 'is_launched': true,
      },
      {
        'id': 2, 'name': 'Lawn Care', 'slug': 'lawn-care', 'icon_name': 'grass',
        'what_we_cover': 'Mowing and edging.', 'worker_noun': 'lawn care specialists', 'is_launched': false,
      },
    ],
  },
];

class _Server {
  _Server({this.refine = const {}, this.createStatus = 'new'});

  final Map<String, dynamic> refine;
  final String createStatus;
  final requests = <http.Request>[];

  http.Client client() => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('/catalog/categories/')) return http.Response(jsonEncode(_catalogJson), 200);
        if (path.endsWith('/chat/refine/')) return http.Response(jsonEncode(refine), 200);
        if (path.endsWith('/categories/suggest/')) {
          return http.Response(jsonEncode({'categories': [], 'keywords': []}), 200);
        }
        if (request.method == 'POST' && path.endsWith('/requests/')) {
          final waitlisted = createStatus == 'waitlisted';
          return http.Response(
            jsonEncode({
              'request_id': 1,
              'status': createStatus,
              if (waitlisted) 'message': kWaitlistedMessage,
            }),
            201,
          );
        }
        return http.Response(jsonEncode({'requests': [], 'notifications': []}), 200);
      });
}

void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// pumpAndSettle never returns while a progress spinner is on screen (the
// submit button and the chat both show one mid-request), so step the clock a
// bounded number of frames instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _toConfirmation(WidgetTester tester) async {
  await tester.tap(find.text('Today'));
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next')); // location step is prefilled
  await tester.pumpAndSettle();
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, '+1 780 555 0100');
  await tester.pump();
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
  await _settle(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetCatalogForTests();
  });

  group('catalog parsing', () {
    test('is_launched is read per service, and a missing flag means launched', () async {
      final server = _Server();
      await http.runWithClient(() async {
        final groups = await ApiClient().getCatalog(includeUnlaunched: true);
        final services = groups.single.services;
        expect(groups, hasLength(1));
        expect([for (final s in services) (s.slug, s.isLaunched)], [('plumbing', true), ('lawn-care', false)]);
      }, server.client);

      final legacy = ServiceCategory(label: 'x', icon: Icons.build, whatWeCover: '', workerNoun: '', slug: 'x');
      expect(legacy.isLaunched, isTrue);
    });

    test('search suggestions are requested with unlaunched services included', () async {
      final server = _Server();
      await http.runWithClient(() => ApiClient().suggestCategories('mow'), server.client);
      expect(server.requests.single.url.queryParameters, {'q': 'mow', 'include_unlaunched': 'true'});
    });
  });

  group('service list', () {
    testWidgets('only unlaunched services carry a Coming soon badge', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ServiceListPage(
          group: ServiceCategoryGroup(label: 'Trades', icon: Icons.build, slug: 'trades', services: const [_plumbing, _lawn]),
        ),
      ));

      expect(find.text('Plumbing'), findsOneWidget);
      expect(find.text('Lawn Care'), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
      final badgeTile = find.ancestor(of: find.text('Coming soon'), matching: find.byType(Pressable));
      expect(find.descendant(of: badgeTile, matching: find.text('Lawn Care')), findsOneWidget);
      expect(find.descendant(of: badgeTile, matching: find.text('Plumbing')), findsNothing);
    });
  });

  group('detail page', () {
    testWidgets('a launched service reads as today', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CategoryDetailPage(category: _plumbing)));
      expect(find.text('Select this category'), findsOneWidget);
      expect(find.text('HOW IT WORKS'), findsOneWidget);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('Join the waitlist'), findsNothing);
    });

    testWidgets('an unlaunched service explains the waitlist and offers to join it', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CategoryDetailPage(category: _lawn)));
      expect(find.text('Join the waitlist'), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget); // the badge
      expect(find.text('COMING SOON'), findsOneWidget); // the section label
      expect(find.textContaining("isn't open in your area yet"), findsOneWidget);
      expect(find.text('Select this category'), findsNothing);
      expect(find.text('HOW IT WORKS'), findsNothing);
    });

    testWidgets('joining the waitlist confirms the service like selecting one does', (tester) async {
      bool? confirmed;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => confirmed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const CategoryDetailPage(category: _lawn)),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join the waitlist'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });
  });

  group('request form', () {
    testWidgets('a launched service keeps the current consent wording', (tester) async {
      _bigScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen(initialCategory: _plumbing)));
      await _toConfirmation(tester);

      expect(find.text(kServiceRequestConsentText), findsOneWidget);
      expect(find.text(kWaitlistConsentText), findsNothing);
      expect(find.textContaining('once you submit'), findsOneWidget);
    });

    testWidgets('an unlaunched service uses the waitlist consent wording', (tester) async {
      _bigScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen(initialCategory: _lawn)));
      await _toConfirmation(tester);

      expect(find.text(kWaitlistConsentText), findsOneWidget);
      expect(find.text(kServiceRequestConsentText), findsNothing);
      expect(find.textContaining("isn't open yet"), findsOneWidget);
    });

    test('the waitlist consent is exactly the agreed wording', () {
      expect(
        kWaitlistConsentText,
        'I consent to Top-Link AI saving this request and sharing it, including my phone number, '
        'with suitable service providers once this service is available in my area.',
      );
      expect(
        kServiceRequestConsentText,
        'I consent to Top-Link AI sharing the details of this request, including my phone number, '
        'with service providers who may be able to help.',
      );
    });

    testWidgets('submitting a waitlisted request shows the coming-soon message, then goes Home', (tester) async {
      _bigScreen(tester);
      final server = _Server(createStatus: 'waitlisted');
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingScreen(initialCategory: _lawn)));
        await _toConfirmation(tester);
        await _fillAndSubmit(tester);

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(kWaitlistedMessage), findsOneWidget);
        expect(
          kWaitlistedMessage,
          'This service is coming soon in your area. We saved your request and will contact you when it opens.',
        );
        expect(find.byType(HomeScreen), findsNothing);

        await tester.tap(find.text('OK'));
        await _settle(tester);
        expect(find.byType(HomeScreen), findsOneWidget);
      }, server.client);

      final post = server.requests.firstWhere((r) => r.method == 'POST' && r.url.path.endsWith('/requests/'));
      expect(jsonDecode(post.body), containsPair('category', 'lawn-care'));
      expect(jsonDecode(post.body), containsPair('consent', true));
    });

    testWidgets('a launched request goes straight Home with no dialog', (tester) async {
      _bigScreen(tester);
      final server = _Server();
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingScreen(initialCategory: _plumbing)));
        await _toConfirmation(tester);
        await _fillAndSubmit(tester);

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      }, server.client);
    });
  });

  group('history', () {
    testWidgets('a waitlisted request is marked Waitlisted; a new one is not', (tester) async {
      ServiceRequestRecord record(String status) => ServiceRequestRecord(
            id: 1,
            category: 'lawn-care',
            city: 'Edmonton',
            problemDescription: '',
            phone: '1',
            status: status,
            createdAt: DateTime(2026, 1, 1),
          );

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ServiceRequestCard(request: record('waitlisted')))));
      expect(find.text('Waitlisted'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ServiceRequestCard(request: record('new')))));
      expect(find.text('Waitlisted'), findsNothing);
    });
  });

  group('search', () {
    testWidgets('an unlaunched service is found by name and badged; tapping opens the waitlist page', (tester) async {
      final server = _Server();
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CategorySearchView(
              onSelect: (_) {},
              suggestionsFetcher: (_) async => RemoteCategorySuggestions.none,
              child: const SizedBox(),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'lawn');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(find.text('Lawn Care'), findsOneWidget);
        expect(find.text('Coming soon'), findsOneWidget);

        await tester.tap(find.text('Lawn Care'));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryDetailPage), findsOneWidget);
        expect(find.text('Join the waitlist'), findsOneWidget);
      }, server.client);
    });
  });

  group('Ask AI', () {
    Future<void> ask(WidgetTester tester, _Server server) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ChatScreen())));
      await tester.enterText(find.byType(TextField), 'someone to mow my lawn');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
    }

    testWidgets('an unlaunched service gets a waitlist offer, not a dead end', (tester) async {
      _bigScreen(tester);
      final server = _Server(refine: {'category': 'lawn-care', 'launched': false, 'urgency': 'today', 'notes': ''});
      await http.runWithClient(() async {
        await ask(tester, server);

        expect(find.textContaining('coming soon in your area'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Join the waitlist'), findsOneWidget);
        expect(find.text('Continue'), findsNothing);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Join the waitlist'));
        await tester.pumpAndSettle();
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.text('How soon do you need this done?'), findsOneWidget);
      }, server.client);
    });

    testWidgets('a launched service still gets Continue', (tester) async {
      _bigScreen(tester);
      final server = _Server(refine: {'category': 'plumbing', 'launched': true, 'urgency': 'today', 'notes': ''});
      await http.runWithClient(() async {
        await ask(tester, server);

        expect(find.widgetWithText(OutlinedButton, 'Continue'), findsOneWidget);
        expect(find.text('Join the waitlist'), findsNothing);
      }, server.client);
    });

    testWidgets('no recognised service still offers nothing to continue with', (tester) async {
      _bigScreen(tester);
      final server = _Server(refine: {'category': null, 'launched': false, 'urgency': 'exploring', 'notes': ''});
      await http.runWithClient(() async {
        await ask(tester, server);

        expect(find.textContaining("couldn't quite tell"), findsOneWidget);
        expect(find.byType(OutlinedButton), findsNothing);
      }, server.client);
    });
  });
}
