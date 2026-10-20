import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/api_client.dart';
import 'package:toplinkai_app/api/provider_profile.dart';
import 'package:toplinkai_app/api/service_request.dart';
import 'package:toplinkai_app/client/client_sign_in_screen.dart';
import 'package:toplinkai_app/home/home_screen.dart';
import 'package:toplinkai_app/onboarding/onboarding_screen.dart';
import 'package:toplinkai_app/onboarding/service_category.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';
import 'package:toplinkai_app/provider/provider_home_screen.dart';
import 'package:toplinkai_app/provider/provider_leads_tab.dart';
import 'package:toplinkai_app/provider/provider_session.dart';
import 'package:toplinkai_app/role/app_role.dart';

// The client side now needs a signed-in account: sign-in comes at the end of the
// request questions, "Your requests" is the account's own list, and the client
// marks a job complete from there. The provider side gets a Leads tab.

const _plumbing = ServiceCategory(
  label: 'Plumbing',
  icon: Icons.plumbing,
  whatWeCover: 'Pipes and drains.',
  workerNoun: 'plumbers',
  slug: 'plumbing',
);

Map<String, dynamic> _request({List<Map<String, dynamic>> accepted = const []}) => {
      'id': 7,
      'category': 'plumbing',
      'city': 'Edmonton',
      'problem_description': 'Leaking sink',
      'phone': '+17805550100',
      'status': 'new',
      'urgency': 'today',
      'created_at': '2026-10-10T12:00:00Z',
      'accepted_offers': accepted,
    };

Map<String, dynamic> _accepted({bool completed = false, bool canComplete = true}) => {
      'offer_id': 42,
      'provider': {'id': 3, 'business_name': 'Ace Plumbing'},
      'hired': completed,
      'job_completed': completed,
      'can_complete': canComplete && !completed,
    };

/// A fake backend that records what the app sends.
class _Backend {
  _Backend({this.signInStatus = 200, this.signInDetail, this.createStatuses = const [201]});

  final int signInStatus;
  final String? signInDetail;
  final List<int> createStatuses;
  final requests = <http.Request>[];
  var _creates = 0;
  var completed = false;
  List<Map<String, dynamic>> leads = [];

  Iterable<http.Request> to(String suffix) => requests.where((r) => r.url.path.endsWith(suffix));

  http.Client get client => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('/accounts/google/')) {
          if (signInStatus != 200) {
            return http.Response(jsonEncode({'detail': signInDetail ?? 'No.'}), signInStatus);
          }
          return http.Response(
            jsonEncode({'access': 'new-access', 'refresh': 'new-refresh', 'email': 'pat@example.com', 'full_name': 'Pat', 'is_new_account': true}),
            200,
          );
        }
        if (path.endsWith('/accounts/token/refresh/')) return http.Response(jsonEncode({'detail': 'expired'}), 401);
        if (request.method == 'POST' && path.endsWith('/requests/')) {
          final status = createStatuses[_creates < createStatuses.length ? _creates : createStatuses.length - 1];
          _creates++;
          if (status != 201) return http.Response(jsonEncode({'detail': 'Given token not valid'}), status);
          return http.Response(jsonEncode({'request_id': 7, 'status': 'new'}), 201);
        }
        if (path.endsWith('/requests/7/complete/')) {
          completed = true;
          return http.Response(jsonEncode(_request(accepted: [_accepted(completed: true)])), 200);
        }
        if (path.endsWith('/requests/mine/')) {
          return http.Response(jsonEncode({'requests': [_request(accepted: [_accepted(completed: completed)])]}), 200);
        }
        if (path.endsWith('/provider/leads/')) return http.Response(jsonEncode({'leads': leads}), 200);
        if (path.endsWith('/catalog/categories/')) return http.Response(jsonEncode([]), 200);
        return http.Response(jsonEncode({'requests': [], 'notifications': []}), 200);
      });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _toSubmit(WidgetTester tester) async {
  await tester.tap(find.text('Today'));
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('location-field')), 'T5J 0N3');
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
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
    FlutterSecureStorage.setMockInitialValues({});
    resetCatalogForTests();
  });

  group('signing in comes after the request questions', () {
    testWidgets('a signed-out client is asked to sign in at the end, then the request is sent as them', (tester) async {
      _bigScreen(tester);
      final backend = _Backend();
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: OnboardingScreen(initialCategory: _plumbing, idTokenProvider: () async => 'google-token'),
        ));
        await _toSubmit(tester);

        // All the questions were answered; only now are they asked to sign in.
        expect(find.byKey(const Key('client-sign-in-title')), findsOneWidget);
        expect(backend.to('/requests/'), isEmpty);

        await tester.tap(find.byKey(const Key('client-google-sign-in')));
        await _settle(tester);
        expect(find.byType(HomeScreen), findsOneWidget);
      }, () => backend.client);

      final signIn = backend.to('/accounts/google/').single;
      expect(jsonDecode(signIn.body), {'id_token': 'google-token'});
      final post = backend.to('/requests/').single;
      expect(post.headers['Authorization'], 'Bearer new-access');
      expect(jsonDecode(post.body), containsPair('category', 'plumbing'));
      expect(await AuthStorage.getAccessToken(), 'new-access');
    });

    testWidgets('an already signed-in client is not asked again', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'old-access', refresh: 'old-refresh');
      final backend = _Backend();
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingScreen(initialCategory: _plumbing)));
        await _toSubmit(tester);
        expect(find.byKey(const Key('client-sign-in-title')), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      }, () => backend.client);

      expect(backend.to('/accounts/google/'), isEmpty);
      expect(backend.to('/requests/').single.headers['Authorization'], 'Bearer old-access');
    });

    testWidgets('"Not now" sends nothing and keeps their answers', (tester) async {
      _bigScreen(tester);
      final backend = _Backend();
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingScreen(initialCategory: _plumbing)));
        await _toSubmit(tester);
        await tester.tap(find.byKey(const Key('client-sign-in-not-now')));
        await _settle(tester);

        expect(find.byKey(const Key('client-sign-in-title')), findsNothing);
        expect(find.byType(HomeScreen), findsNothing);
        expect(find.widgetWithText(ElevatedButton, 'Continue'), findsOneWidget); // can try again
      }, () => backend.client);

      expect(backend.to('/requests/'), isEmpty);
    });

    testWidgets('a provider email is refused with the server\'s message and nothing is sent', (tester) async {
      _bigScreen(tester);
      final backend = _Backend(
        signInStatus: 409,
        signInDetail: 'This email already belongs to a provider account. Use a different Google account.',
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: OnboardingScreen(initialCategory: _plumbing, idTokenProvider: () async => 'google-token'),
        ));
        await _toSubmit(tester);
        await tester.tap(find.byKey(const Key('client-google-sign-in')));
        await _settle(tester);

        expect(find.byKey(const Key('client-sign-in-error')), findsOneWidget);
        expect(find.textContaining('provider account'), findsOneWidget);
      }, () => backend.client);

      expect(backend.to('/requests/'), isEmpty);
      expect(await AuthStorage.isLoggedIn(), isFalse);
    });

    testWidgets('a saved login that has expired sends them back through sign-in, then the request goes', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'stale-access', refresh: 'stale-refresh');
      final backend = _Backend(createStatuses: [401, 201]);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: OnboardingScreen(initialCategory: _plumbing, idTokenProvider: () async => 'google-token'),
        ));
        await _toSubmit(tester);
        expect(find.byKey(const Key('client-sign-in-title')), findsOneWidget);

        await tester.tap(find.byKey(const Key('client-google-sign-in')));
        await _settle(tester);
        expect(find.byType(HomeScreen), findsOneWidget);
      }, () => backend.client);

      final posts = backend.to('/requests/').toList();
      expect(posts.map((r) => r.headers['Authorization']), ['Bearer stale-access', 'Bearer new-access']);
    });
  });

  group('your requests', () {
    Future<void> pumpHistory(WidgetTester tester, _Backend backend) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: HistoryTab(idTokenProvider: () async => 'google-token')),
      ));
      await _settle(tester);
    }

    testWidgets('signed out, it offers to sign in and shows nothing', (tester) async {
      _bigScreen(tester);
      final backend = _Backend();
      await http.runWithClient(() async {
        await pumpHistory(tester, backend);
        expect(find.byKey(const Key('history-signed-out')), findsOneWidget);
        expect(find.text('Leaking sink'), findsNothing);
      }, () => backend.client);

      expect(backend.to('/requests/mine/'), isEmpty); // not even asked
    });

    testWidgets('signed in, it lists the requests and who accepted, without any device id', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'client-access', refresh: 'client-refresh');
      final backend = _Backend();
      await http.runWithClient(() async {
        await pumpHistory(tester, backend);
        expect(find.text('Plumbing'), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('request-status')), matching: find.text('Accepted by Ace Plumbing')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('accepted-42')), matching: find.text('Ace Plumbing')), findsOneWidget);
        expect(find.byKey(const Key('complete-42')), findsOneWidget);
      }, () => backend.client);

      final list = backend.to('/requests/mine/').single;
      expect(list.headers['Authorization'], 'Bearer client-access');
      expect(list.url.queryParameters, isEmpty);
    });

    testWidgets('the client marks a job complete after confirming', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'client-access', refresh: 'client-refresh');
      final backend = _Backend();
      await http.runWithClient(() async {
        await pumpHistory(tester, backend);
        await tester.tap(find.byKey(const Key('complete-42')));
        await tester.pumpAndSettle();
        expect(find.text('Mark job complete?'), findsOneWidget);
        expect(backend.to('/complete/'), isEmpty); // nothing yet: they have to confirm

        await tester.tap(find.byKey(const Key('confirm-complete')));
        await _settle(tester);
        // the status pill says Completed; the provider's row doesn't say it again
        expect(find.descendant(of: find.byKey(const Key('request-status')), matching: find.text('Completed')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('accepted-42')), matching: find.text('Completed')), findsNothing);
        expect(find.byKey(const Key('complete-42')), findsNothing);
      }, () => backend.client);

      final post = backend.to('/requests/7/complete/').single;
      expect(jsonDecode(post.body), {'offer_id': 42});
      expect(post.headers['Authorization'], 'Bearer client-access');
    });

    testWidgets('"Not yet" in the confirmation changes nothing', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'client-access', refresh: 'client-refresh');
      final backend = _Backend();
      await http.runWithClient(() async {
        await pumpHistory(tester, backend);
        await tester.tap(find.byKey(const Key('complete-42')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Not yet'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('complete-42')), findsOneWidget);
      }, () => backend.client);

      expect(backend.to('/complete/'), isEmpty);
    });

    testWidgets('a job that is already complete shows Completed and no button', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ServiceRequestCard(
            request: ServiceRequestRecord.fromJson(_request(accepted: [_accepted(completed: true)])),
            onMarkComplete: (_) {},
          ),
        ),
      ));
      // The pill says Completed once; the provider's row doesn't repeat it when there is only one provider.
      expect(find.descendant(of: find.byKey(const Key('request-status')), matching: find.text('Completed')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('accepted-42')), matching: find.text('Completed')), findsNothing);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.byKey(const Key('complete-42')), findsNothing);
    });

    testWidgets('with several providers the row says which one was completed', (tester) async {
      final other = _accepted()..['offer_id'] = 43;
      other['can_complete'] = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ServiceRequestCard(
            request: ServiceRequestRecord.fromJson(_request(accepted: [_accepted(completed: true), other])),
            onMarkComplete: (_) {},
          ),
        ),
      ));
      expect(find.descendant(of: find.byKey(const Key('accepted-42')), matching: find.text('Completed')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('accepted-43')), matching: find.text('Completed')), findsNothing);
    });

    testWidgets('once one provider is completed, the others cannot also be marked complete', (tester) async {
      final other = _accepted()..['offer_id'] = 43;
      other['can_complete'] = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ServiceRequestCard(
            request: ServiceRequestRecord.fromJson(_request(accepted: [_accepted(completed: true), other])),
            onMarkComplete: (_) {},
          ),
        ),
      ));
      expect(find.byKey(const Key('complete-43')), findsNothing);
    });
  });

  group('the provider\'s leads', () {
    Map<String, dynamic> lead(int id, String status, {String? description, String? clientName}) => {
          'offer_id': id,
          'request_id': 7,
          'service': {'slug': 'plumbing', 'name': 'Plumbing'},
          'city': 'Edmonton',
          'urgency': 'today',
          'status': status,
          'description': ?description,
          'client_name': ?clientName,
        };

    Future<void> pumpLeads(WidgetTester tester, _Backend backend) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProviderLeadsTab(session: AuthSession(), onSessionExpired: () {})),
      ));
      await _settle(tester);
    }

    testWidgets('shows what the provider may see, and never a phone number', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'pro-access', refresh: 'pro-refresh');
      final backend = _Backend()
        ..leads = [
          lead(1, 'accepted', description: 'Leaking sink', clientName: 'Pat C.'),
          lead(2, 'awaiting_reply'),
        ];
      await http.runWithClient(() async {
        await pumpLeads(tester, backend);
        expect(find.byKey(const Key('lead-1')), findsOneWidget);
        expect(find.text('Accepted'), findsOneWidget);
        expect(find.text('Pat C.'), findsOneWidget);
        expect(find.text('Leaking sink'), findsOneWidget);
        expect(find.text('Awaiting your reply'), findsOneWidget);
        expect(find.textContaining('780'), findsNothing);
      }, () => backend.client);

      expect(backend.to('/provider/leads/').single.headers['Authorization'], 'Bearer pro-access');
    });

    testWidgets('an empty list says so', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'pro-access', refresh: 'pro-refresh');
      final backend = _Backend();
      await http.runWithClient(() async {
        await pumpLeads(tester, backend);
        expect(find.byKey(const Key('provider-leads-empty')), findsOneWidget);
      }, () => backend.client);
    });

    testWidgets('a provider approved home has Profile and Leads tabs', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'pro-access', refresh: 'pro-refresh');
      final backend = _Backend()..leads = [lead(1, 'declined')];
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: ProviderHomeScreen(
            profile: const ProviderProfileData(
              businessName: 'Ace Plumbing',
              phone: '+17805550100',
              email: 'a@b.co',
              categories: ['plumbing'],
              cities: ['Edmonton'],
              status: ProviderStatus.approved,
            ),
            session: AuthSession(),
            onEdit: () {},
            onRefresh: () async {},
            onSignOut: () {},
            onSwitchRole: () {},
            onSessionExpired: () {},
          ),
        ));
        await _settle(tester);
        expect(find.byKey(const Key('provider-home-title')), findsOneWidget);

        await tester.tap(find.byKey(const Key('tab-leads')));
        await _settle(tester);
        expect(find.byKey(const Key('provider-leads-title')), findsOneWidget);
        expect(find.text('Declined'), findsOneWidget);
      }, () => backend.client);
    });
  });

  group('switching role', () {
    testWidgets('signs the person out, so one role\'s login is never used as the other\'s', (tester) async {
      await AuthStorage.save(access: 'pro-access', refresh: 'pro-refresh');
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(onPressed: () => switchRole(context), child: const Text('switch')),
        ),
      ));
      await tester.tap(find.text('switch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(await AuthStorage.isLoggedIn(), isFalse);
    });
  });

  testWidgets('the sign-in screen can be pumped on its own and says why', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ClientSignInScreen(api: ApiClient(), idTokenProvider: () async => 'x', title: 'Sign in to see your requests'),
    ));
    expect(find.text('Sign in to see your requests'), findsOneWidget);
    expect(find.byKey(const Key('client-google-sign-in')), findsOneWidget);
  });
}
