import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/provider_profile.dart';
import 'package:toplinkai_app/onboarding/service_category.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';
import 'package:toplinkai_app/provider/provider_pending_screen.dart';
import 'package:toplinkai_app/provider/provider_registration_screen.dart';
import 'package:toplinkai_app/provider/provider_session.dart';
import 'package:toplinkai_app/provider/provider_widgets.dart';
import 'package:toplinkai_app/widgets/coming_soon_badge.dart';

// The provider sign-up form: cities (Edmonton, with a waitlist for the rest), the sector list (counts and "Coming
// soon" services), the wider consent wording and the placeholder; and the pending screen.

ServiceCategory service(String slug, String label, {bool launched = true}) => ServiceCategory(
      label: label,
      icon: Icons.build,
      whatWeCover: '',
      workerNoun: 'pros',
      slug: slug,
      isLaunched: launched,
    );

void useCatalog() {
  final trades = [service('plumbing', 'Plumbing'), service('hvac', 'HVAC'), service('roofing', 'Roofing', launched: false)];
  final home = [service('cleaning', 'Cleaning Services', launched: false)];
  serviceCategoryGroups = [
    ServiceCategoryGroup(label: 'Trades & Professional Services', icon: Icons.build, slug: 'trades', services: trades),
    ServiceCategoryGroup(label: 'Home Services', icon: Icons.home, slug: 'home', services: home),
  ];
  serviceCategories = [...trades, ...home];
}

void bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthStorage.save(access: 'tok-1', refresh: 'ref-1');
    resetCatalogForTests();
    useCatalog();
  });

  tearDown(resetCatalogForTests);

  /// Pumps the form with a server that accepts a registration and echoes it back.
  Future<List<http.Request>> pumpForm(
    WidgetTester tester, {
    ProviderProfileData? initial,
    required Future<void> Function(List<http.Request> requests, List<ProviderProfileData> saved) body,
  }) async {
    bigScreen(tester);
    final requests = <http.Request>[];
    final saved = <ProviderProfileData>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/provider/profile/')) {
        final sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({...sent, 'status': 'pending'}), request.method == 'POST' ? 201 : 200);
      }
      return http.Response('{}', 500); // the catalog cannot load: the groups set above stay
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: ProviderRegistrationScreen(
          session: AuthSession(),
          initial: initial,
          defaultEmail: 'pro@example.com',
          onSaved: saved.add,
          onSessionExpired: () {},
        ),
      ));
      await settle(tester);
      await body(requests, saved);
    }, () => client);
    return requests;
  }

  Future<void> expandTrades(WidgetTester tester) async {
    await tester.tap(find.text('Trades & Professional Services'));
    await settle(tester);
  }

  // -------------------------------------------------------------------------------------------------
  group('cities', () {
    testWidgets('only Edmonton can be chosen; the others are coming soon with a waitlist', (tester) async {
      await pumpForm(tester, body: (_, _) async {
        expect(find.byKey(const Key('city-Edmonton')), findsOneWidget);
        for (final city in ['Calgary', 'Fort McMurray', 'Red Deer']) {
          expect(find.byKey(Key('city-$city')), findsNothing, reason: '$city is not a city you can serve yet');
          expect(find.byKey(Key('waitlist-$city')), findsOneWidget);
        }
        expect(find.byType(ComingSoonBadge), findsNWidgets(3));
        expect(find.textContaining('open in Edmonton for now'), findsOneWidget);
      });
    });

    testWidgets('tapping a coming-soon city joins its waitlist, and again leaves it', (tester) async {
      await pumpForm(tester, body: (_, _) async {
        await tester.tap(find.byKey(const Key('waitlist-Calgary')));
        await tester.pump();
        expect(find.text('On the waitlist'), findsOneWidget);
        expect(find.byType(ComingSoonBadge), findsNWidgets(2));
        await tester.tap(find.byKey(const Key('waitlist-Calgary')));
        await tester.pump();
        expect(find.text('On the waitlist'), findsNothing);
        expect(find.byType(ComingSoonBadge), findsNWidgets(3));
      });
    });

    testWidgets('joining a waitlist does not count as a city you serve', (tester) async {
      await pumpForm(tester, body: (requests, saved) async {
        await tester.tap(find.byKey(const Key('waitlist-Calgary')));
        await tester.tap(find.text('Submit for review'));
        await settle(tester);
        expect(find.byKey(const Key('city-error')), findsOneWidget);
        expect(requests.where((r) => r.method == 'POST'), isEmpty);
      });
    });

    testWidgets('the profile is sent with Edmonton as the city and the waitlist cities separately', (tester) async {
      await pumpForm(tester, body: (requests, saved) async {
        await tester.enterText(find.byKey(const Key('field-business-name')), 'Ace Plumbing');
        await tester.enterText(find.byKey(const Key('field-phone')), '7805550100');
        await tester.pump();
        expect(tester.widget<TextField>(find.byKey(const Key('field-phone'))).controller!.text, '(780) 555-0100');
        await expandTrades(tester);
        await tester.tap(find.byKey(const Key('service-plumbing')));
        await tester.tap(find.byKey(const Key('city-Edmonton')));
        await tester.tap(find.byKey(const Key('waitlist-Calgary')));
        await tester.tap(find.byKey(const Key('waitlist-Red Deer')));
        await tester.tap(find.byKey(const Key('sms-consent')));
        await tester.pump();
        await tester.tap(find.text('Submit for review'));
        await settle(tester);

        final body = jsonDecode(requests.firstWhere((r) => r.method == 'POST').body) as Map<String, dynamic>;
        expect(body['cities'], ['Edmonton']);
        expect(body['waitlist_cities'], ['Calgary', 'Red Deer']);
        expect(body['phone'], '+17805550100');
        expect(saved, hasLength(1));
        expect(saved.single.waitlistCities, ['Calgary', 'Red Deer']);
      });
    });

    testWidgets('editing a profile shows its waitlist, and a city saved before the limit moves to the waitlist', (tester) async {
      const initial = ProviderProfileData(
        businessName: 'Ace',
        phone: '+17805550100',
        email: 'pro@example.com',
        categories: ['plumbing'],
        cities: ['Edmonton', 'Calgary'], // saved before the cities were limited
        waitlistCities: ['Red Deer'],
        status: ProviderStatus.approved,
      );
      await pumpForm(tester, initial: initial, body: (requests, saved) async {
        expect(tester.widget<FilterChip>(find.byKey(const Key('city-Edmonton'))).selected, isTrue);
        expect(tester.widget<FilterChip>(find.byKey(const Key('waitlist-Calgary'))).selected, isTrue);
        expect(tester.widget<FilterChip>(find.byKey(const Key('waitlist-Red Deer'))).selected, isTrue);
        expect(tester.widget<FilterChip>(find.byKey(const Key('waitlist-Fort McMurray'))).selected, isFalse);
        await tester.tap(find.text('Save changes'));
        await settle(tester);
        final body = jsonDecode(requests.firstWhere((r) => r.method == 'PATCH').body) as Map<String, dynamic>;
        expect(body['cities'], ['Edmonton']);
        expect(body['waitlist_cities'], ['Calgary', 'Red Deer']);
      });
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('the sector list', () {
    testWidgets('every sector says how many services it has, and how many are chosen', (tester) async {
      await pumpForm(tester, body: (_, _) async {
        expect(find.byKey(const Key('group-count-trades')), findsOneWidget);
        expect(tester.widget<Text>(find.byKey(const Key('group-count-trades'))).data, '3 services');
        expect(tester.widget<Text>(find.byKey(const Key('group-count-home'))).data, '1 service');

        await expandTrades(tester);
        await tester.tap(find.byKey(const Key('service-plumbing')));
        await tester.pump();
        expect(tester.widget<Text>(find.byKey(const Key('group-count-trades'))).data, '1 of 3 selected');
        await tester.tap(find.byKey(const Key('service-hvac')));
        await tester.pump();
        expect(tester.widget<Text>(find.byKey(const Key('group-count-trades'))).data, '2 of 3 selected');
        expect(tester.widget<Text>(find.byKey(const Key('group-count-home'))).data, '1 service');

        await tester.tap(find.byKey(const Key('service-plumbing')));
        await tester.tap(find.byKey(const Key('service-hvac')));
        await tester.pump();
        expect(tester.widget<Text>(find.byKey(const Key('group-count-trades'))).data, '3 services');
      });
    });

    testWidgets('services that are not open yet are marked Coming soon, the rest are not', (tester) async {
      await pumpForm(tester, body: (_, _) async {
        await expandTrades(tester);
        expect(find.byKey(const Key('coming-soon-roofing')), findsOneWidget);
        expect(find.byKey(const Key('coming-soon-plumbing')), findsNothing);
        expect(find.byKey(const Key('coming-soon-hvac')), findsNothing);
        // providers can still sign up for an upcoming service
        await tester.tap(find.byKey(const Key('service-roofing')));
        await tester.pump();
        expect(tester.widget<FilterChip>(find.byKey(const Key('service-roofing'))).selected, isTrue);
        expect(tester.widget<Text>(find.byKey(const Key('group-count-trades'))).data, '1 of 3 selected');
      });
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('the rest of the form', () {
    testWidgets('the business name field has a placeholder like the others', (tester) async {
      await pumpForm(tester, body: (_, _) async {
        expect(tester.widget<TextField>(find.byKey(const Key('field-business-name'))).decoration!.hintText, 'e.g. Ace Plumbing');
        expect(tester.widget<TextField>(find.byKey(const Key('field-phone'))).decoration!.hintText, 'e.g. 780 555 0100');
      });
    });

    testWidgets('the consent covers texts, in-app messages and notifications', (tester) async {
      await pumpForm(tester, body: (_, _) async {
        expect(kProviderSmsConsentText, contains('text message'));
        expect(kProviderSmsConsentText, contains('messages and notifications in the app'));
        expect(kProviderSmsConsentText, contains('STOP'));
        expect(kProviderSmsConsentText, contains('Settings'));
        expect(find.text(kProviderSmsConsentText), findsOneWidget);
      });
    });

    testWidgets('without the consent the form says to agree to be contacted', (tester) async {
      await pumpForm(tester, body: (requests, _) async {
        await tester.enterText(find.byKey(const Key('field-business-name')), 'Ace');
        await tester.enterText(find.byKey(const Key('field-phone')), '7805550100');
        await expandTrades(tester);
        await tester.tap(find.byKey(const Key('service-plumbing')));
        await tester.tap(find.byKey(const Key('city-Edmonton')));
        await tester.tap(find.text('Submit for review'));
        await settle(tester);
        expect(find.text(kProviderSmsConsentRequired), findsOneWidget);
        expect(kProviderSmsConsentRequired, contains('contacted'));
        expect(requests.where((r) => r.method == 'POST'), isEmpty);
      });
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('the provider profile card and the pending screen', () {
    ProviderProfileData profile(ProviderStatus status, {double? average, int count = 0}) => ProviderProfileData.fromJson({
          'business_name': 'Northside Handyman',
          'phone': '+17805550102',
          'email': 'new@example.com',
          'categories': ['plumbing'],
          'cities': ['Edmonton'],
          'status': status.name,
          'rating_average': average,
          'review_count': count,
        });

    testWidgets('an approved provider sees their rating and their phone formatted', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProviderProfileCard(profile: profile(ProviderStatus.approved, average: 4.5, count: 2))),
      ));
      expect(find.byKey(const Key('profile-rating')), findsOneWidget);
      expect(find.text('(2 reviews)'), findsOneWidget);
      expect(find.text('(780) 555-0102'), findsOneWidget);
      expect(find.text('+17805550102'), findsNothing);
    });

    testWidgets('a provider who is not approved yet is not shown "No reviews yet"', (tester) async {
      for (final status in [ProviderStatus.pending, ProviderStatus.rejected]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProviderProfileCard(profile: profile(status)))));
        expect(find.byKey(const Key('profile-rating')), findsNothing, reason: status.name);
        expect(find.text('No reviews yet'), findsNothing, reason: status.name);
      }
    });

    testWidgets('the pending screen has a title that is not the status pill, and no rating', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: ProviderPendingScreen(
          profile: profile(ProviderStatus.pending),
          onRefresh: () async {},
          onEdit: () {},
          onSignOut: () {},
          onSwitchRole: () {},
        ),
      ));
      expect(find.text('Pending review'), findsOneWidget, reason: 'the pill, once');
      expect(tester.widget<Text>(find.byKey(const Key('review-title'))).data, "We're reviewing your profile");
      expect(find.text('No reviews yet'), findsNothing);
      expect(find.textContaining('Thanks, Northside Handyman.'), findsOneWidget);
    });

    testWidgets('a rejected profile keeps its own title and note', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: ProviderPendingScreen(
          profile: ProviderProfileData.fromJson({
            'business_name': 'Northside Handyman',
            'phone': '+17805550102',
            'email': 'new@example.com',
            'categories': ['plumbing'],
            'cities': ['Edmonton'],
            'status': 'rejected',
            'review_note': 'Please add your licence number.',
          }),
          onRefresh: () async {},
          onEdit: () {},
          onSignOut: () {},
          onSwitchRole: () {},
        ),
      ));
      expect(tester.widget<Text>(find.byKey(const Key('review-title'))).data, 'Not approved yet');
      expect(find.byKey(const Key('review-note')), findsOneWidget);
    });
  });
}
