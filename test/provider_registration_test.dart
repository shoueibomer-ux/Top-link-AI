import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/api_client.dart';
import 'package:toplinkai_app/api/provider_profile.dart';
import 'package:toplinkai_app/onboarding/phone_validation.dart';
import 'package:toplinkai_app/onboarding/service_category.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';
import 'package:toplinkai_app/provider/google_sign_in_service.dart';
import 'package:toplinkai_app/provider/provider_gate.dart';
import 'package:toplinkai_app/provider/provider_sign_in_screen.dart';
import 'package:toplinkai_app/provider/provider_widgets.dart';
import 'package:toplinkai_app/role/app_role.dart';
import 'package:toplinkai_app/role/role_choice_screen.dart';
import 'package:toplinkai_app/role/root_gate.dart';

// Role choice, then the provider journey: Google sign-in -> registration form
// -> pending review -> provider home (with edit). The backend is faked with a
// MockClient and Google with a stand-in token, so nothing here touches the
// network.

Map<String, dynamic> _profileJson({
  String status = 'pending',
  String note = '',
  String name = 'Ace Plumbing',
  String bio = 'Family-run since 2005.',
}) =>
    {
      'business_name': name,
      'phone': '+17805550100',
      'email': 'office@ace.example',
      'categories': ['plumbing'],
      'cities': ['Edmonton'],
      'bio': bio,
      'status': status,
      'review_note': note,
    };

class FakeBackend {
  Map<String, dynamic>? profile;
  int expiredReadsBeforeSuccess = 0;
  bool refreshFails = false;
  String? signInError;
  int signInStatus = 200;
  String? profileReadApiKeyError;
  String? saveError;
  final requests = <http.Request>[];

  http.Client client() => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        final method = request.method;
        http.Response json(int status, Object body) => http.Response(jsonEncode(body), status);

        if (path.endsWith('/provider/auth/google/')) {
          if (signInStatus != 200) return json(signInStatus, {'detail': signInError ?? 'Not allowed.'});
          return json(200, {
            'access': 'access-1',
            'refresh': 'refresh-1',
            'email': 'pro@example.com',
            'full_name': 'Pat Provider',
            'is_new_account': profile == null,
            'profile': profile,
          });
        }
        if (path.endsWith('/provider/profile/')) {
          if (profileReadApiKeyError != null) return json(401, {'detail': profileReadApiKeyError});
          if (expiredReadsBeforeSuccess > 0) {
            expiredReadsBeforeSuccess--;
            return json(401, {'detail': 'Given token not valid for any token type'});
          }
          if (method == 'GET') return profile == null ? json(404, {'detail': 'none'}) : json(200, profile!);
          if (saveError != null) return json(400, {'detail': saveError});
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (method == 'POST') {
            profile = {...body, 'status': 'pending', 'review_note': ''};
            return json(201, profile!);
          }
          profile = {...?profile, ...body};
          return json(200, profile!);
        }
        if (path.endsWith('/accounts/token/refresh/')) {
          return refreshFails
              ? json(401, {'detail': 'Token is invalid'})
              : json(200, {'access': 'access-2', 'refresh': 'refresh-2'});
        }
        if (path.endsWith('/accounts/me/')) {
          return json(200, {'email': 'pro@example.com', 'role': 'provider', 'full_name': 'Pat', 'provider_profile': null});
        }
        return json(404, {'detail': 'not faked'});
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

Future<void> _pumpGate(WidgetTester tester, {Future<String> Function()? idToken}) async {
  await tester.pumpWidget(MaterialApp(
    home: ProviderGate(idTokenProvider: idToken ?? () async => 'dev-fake:pro@example.com'),
  ));
  await _settle(tester);
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.tap(find.text('Continue with Google'));
  await _settle(tester);
}

Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('field-business-name')), 'Ace Plumbing');
  await tester.enterText(find.byKey(const Key('field-phone')), '(780) 555-0100');
  await tester.tap(find.byKey(const Key('service-plumbing')));
  await tester.tap(find.byKey(const Key('city-Edmonton')));
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    resetCatalogForTests();
  });

  group('choosing a role', () {
    test('the choice is remembered, and can be forgotten', () async {
      expect(await RoleStorage.load(), isNull);
      await RoleStorage.save(AppRole.provider);
      expect(await RoleStorage.load(), AppRole.provider);
      await RoleStorage.save(AppRole.client);
      expect(await RoleStorage.load(), AppRole.client);
      await RoleStorage.clear();
      expect(await RoleStorage.load(), isNull);
    });

    testWidgets('the role screen offers both options', (tester) async {
      AppRole? chosen;
      await tester.pumpWidget(MaterialApp(home: RoleChoiceScreen(onChosen: (role) => chosen = role)));
      expect(find.text('I need a service'), findsOneWidget);
      expect(find.text("I'm a service provider"), findsOneWidget);

      await tester.tap(find.byKey(const Key('role-provider')));
      expect(chosen, AppRole.provider);
      await tester.tap(find.byKey(const Key('role-client')));
      expect(chosen, AppRole.client);
    });

    testWidgets('a fresh install asks; choosing "I need a service" opens the client flow and is remembered',
        (tester) async {
      _bigScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: RootGate()));
      await _settle(tester);
      expect(find.byType(RoleChoiceScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('role-client')));
      await _settle(tester);
      expect(find.text('What do you need help with?'), findsOneWidget);
      expect(await RoleStorage.load(), AppRole.client);
    });

    testWidgets('a saved client choice skips the role screen', (tester) async {
      _bigScreen(tester);
      SharedPreferences.setMockInitialValues({'app_role': 'client'});
      await tester.pumpWidget(const MaterialApp(home: RootGate()));
      await _settle(tester);
      expect(find.byType(RoleChoiceScreen), findsNothing);
      expect(find.text('What do you need help with?'), findsOneWidget);
    });

    testWidgets('choosing "I\'m a service provider" opens provider sign-in and is remembered', (tester) async {
      _bigScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: RootGate()));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('role-provider')));
      await _settle(tester);
      expect(find.text('Provider sign-in'), findsOneWidget);
      expect(await RoleStorage.load(), AppRole.provider);
    });

    testWidgets('a saved provider choice goes straight to the provider side', (tester) async {
      SharedPreferences.setMockInitialValues({'app_role': 'provider'});
      await tester.pumpWidget(const MaterialApp(home: RootGate()));
      await _settle(tester);
      expect(find.text('Provider sign-in'), findsOneWidget);
    });

    testWidgets('"I need a service instead" on provider sign-in goes back to the role screen', (tester) async {
      _bigScreen(tester);
      SharedPreferences.setMockInitialValues({'app_role': 'provider'});
      await tester.pumpWidget(const MaterialApp(home: RootGate()));
      await _settle(tester);
      await tester.tap(find.text('I need a service instead'));
      await _settle(tester);
      expect(find.byType(RoleChoiceScreen), findsOneWidget);
      expect(await RoleStorage.load(), isNull);
    });
  });

  group('the provider journey', () {
    testWidgets('sign in with Google -> registration form with the Google email filled in', (tester) async {
      _bigScreen(tester);
      final backend = FakeBackend();
      await http.runWithClient(() async {
        await _pumpGate(tester);
        expect(find.text('Provider sign-in'), findsOneWidget);
        await _signIn(tester);

        expect(find.text('Register your business'), findsOneWidget);
        final email = tester.widget<TextField>(find.byKey(const Key('field-email')));
        expect(email.controller!.text, 'pro@example.com');
        expect(await AuthStorage.getAccessToken(), 'access-1');
      }, backend.client);
      final signIn = backend.requests.firstWhere((r) => r.url.path.endsWith('/auth/google/'));
      expect(jsonDecode(signIn.body), {'id_token': 'dev-fake:pro@example.com'});
    });

    testWidgets('the form says what is missing and what is wrong', (tester) async {
      _bigScreen(tester);
      final backend = FakeBackend();
      await http.runWithClient(() async {
        await _pumpGate(tester);
        await _signIn(tester);

        await tester.tap(find.text('Submit for review'));
        await _settle(tester);
        expect(find.text('Enter your business name.'), findsOneWidget);
        expect(find.text('Enter a phone number.'), findsOneWidget);
        expect(find.byKey(const Key('category-error')), findsOneWidget);
        expect(find.byKey(const Key('city-error')), findsOneWidget);
        expect(backend.requests.where((r) => r.method == 'POST' && r.url.path.endsWith('/provider/profile/')), isEmpty);

        await tester.enterText(find.byKey(const Key('field-phone')), '58792199587');
        await tester.pump();
        expect(find.text(kInvalidPhoneMessage), findsOneWidget);
      }, backend.client);
    });

    testWidgets('submitting sends the profile for review and shows Pending review', (tester) async {
      _bigScreen(tester);
      final backend = FakeBackend();
      await http.runWithClient(() async {
        await _pumpGate(tester);
        await _signIn(tester);
        await _fillForm(tester);
        await tester.tap(find.text('Submit for review'));
        await _settle(tester);

        expect(find.byKey(const Key('review-title')), findsOneWidget);
        expect(find.text('Pending review'), findsWidgets);
        expect(find.text('Ace Plumbing'), findsOneWidget);
      }, backend.client);

      final post = backend.requests.firstWhere((r) => r.method == 'POST' && r.url.path.endsWith('/provider/profile/'));
      expect(jsonDecode(post.body), {
        'business_name': 'Ace Plumbing',
        'phone': '+17805550100',
        'email': 'pro@example.com',
        'categories': ['plumbing'],
        'cities': ['Edmonton'],
        'bio': '',
      });
      expect(post.headers['Authorization'], 'Bearer access-1');
    });

    testWidgets('a returning provider whose profile is pending lands on Pending review', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'access-1', refresh: 'refresh-1');
      final backend = FakeBackend()..profile = _profileJson();
      await http.runWithClient(() async {
        await _pumpGate(tester);
        expect(find.byKey(const Key('review-title')), findsOneWidget);
        expect(find.text('Provider sign-in'), findsNothing);
      }, backend.client);
    });

    testWidgets('Check status moves an approved provider to their home', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'access-1', refresh: 'refresh-1');
      final backend = FakeBackend()..profile = _profileJson();
      await http.runWithClient(() async {
        await _pumpGate(tester);
        expect(find.byKey(const Key('review-title')), findsOneWidget);

        backend.profile = _profileJson(status: 'approved'); // an admin approves
        await tester.tap(find.byKey(const Key('refresh-status')));
        await _settle(tester);

        expect(find.byKey(const Key('provider-home-title')), findsOneWidget);
        expect(find.text('Approved'), findsOneWidget);
        expect(find.text('Ace Plumbing'), findsOneWidget);
        expect(find.byKey(const Key('review-title')), findsNothing);
      }, backend.client);
    });

    testWidgets('an approved provider goes straight to home and can edit their profile', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'access-1', refresh: 'refresh-1');
      final backend = FakeBackend()..profile = _profileJson(status: 'approved');
      await http.runWithClient(() async {
        await _pumpGate(tester);
        expect(find.byKey(const Key('provider-home-title')), findsOneWidget);

        await tester.tap(find.byKey(const Key('edit-profile')));
        await _settle(tester);
        expect(find.text('Edit your profile'), findsOneWidget);
        final name = tester.widget<TextField>(find.byKey(const Key('field-business-name')));
        expect(name.controller!.text, 'Ace Plumbing'); // pre-filled

        await tester.enterText(find.byKey(const Key('field-business-name')), 'Ace Plumbing & Heating');
        await tester.tap(find.text('Save changes'));
        await _settle(tester);

        expect(find.byKey(const Key('provider-home-title')), findsOneWidget);
        expect(find.text('Ace Plumbing & Heating'), findsOneWidget);
        expect(find.text('Approved'), findsOneWidget); // editing didn't un-approve
      }, backend.client);
      final patch = backend.requests.firstWhere((r) => r.method == 'PATCH');
      expect(jsonDecode(patch.body), containsPair('business_name', 'Ace Plumbing & Heating'));
    });

    testWidgets('a rejected provider sees the reviewer\'s note and can fix and resubmit', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'access-1', refresh: 'refresh-1');
      final backend = FakeBackend()..profile = _profileJson(status: 'rejected', note: 'Please add your licence number.');
      await http.runWithClient(() async {
        await _pumpGate(tester);
        expect(find.text('Not approved yet'), findsOneWidget);
        expect(find.text('Please add your licence number.'), findsOneWidget);

        await tester.tap(find.text('Edit and resubmit'));
        await _settle(tester);
        await tester.enterText(find.byKey(const Key('field-bio')), 'Licence 12345');
        await tester.tap(find.text('Save changes'));
        await _settle(tester);
        expect(find.byType(Scaffold), findsWidgets);
      }, backend.client);
      expect(jsonDecode(backend.requests.firstWhere((r) => r.method == 'PATCH').body), containsPair('bio', 'Licence 12345'));
    });

    testWidgets('a server error on save is shown on the form and the form stays', (tester) async {
      _bigScreen(tester);
      final backend = FakeBackend()..saveError = 'Something the app does not know about is wrong.';
      await http.runWithClient(() async {
        await _pumpGate(tester);
        await _signIn(tester);
        await _fillForm(tester);
        await tester.tap(find.text('Submit for review'));
        await _settle(tester);

        expect(find.byKey(const Key('save-error')), findsOneWidget);
        expect(find.text('Something the app does not know about is wrong.'), findsOneWidget);
        expect(find.text('Submit for review'), findsOneWidget); // still on the form, nothing lost
        expect(find.byKey(const Key('review-title')), findsNothing);
      }, backend.client);
    });

    testWidgets('an expired access token is renewed once and the request retried', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'old-access', refresh: 'refresh-1');
      final backend = FakeBackend()
        ..profile = _profileJson(status: 'approved')
        ..expiredReadsBeforeSuccess = 1;
      await http.runWithClient(() async {
        await _pumpGate(tester);
        expect(find.byKey(const Key('provider-home-title')), findsOneWidget);
        expect(await AuthStorage.getAccessToken(), 'access-2');
        expect(await AuthStorage.getRefreshToken(), 'refresh-2');
      }, backend.client);
    });

    testWidgets('when the session can\'t be renewed the provider is sent back to sign-in', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'old-access', refresh: 'old-refresh');
      final backend = FakeBackend()
        ..profile = _profileJson()
        ..expiredReadsBeforeSuccess = 5
        ..refreshFails = true;
      await http.runWithClient(() async {
        await _pumpGate(tester);
        expect(find.text('Provider sign-in'), findsOneWidget);
        expect(find.text('Your session expired. Please sign in again.'), findsOneWidget);
        expect(await AuthStorage.isLoggedIn(), isFalse);
      }, backend.client);
    });

    testWidgets('a wrong API key is reported as a problem, not as an expired session', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'access-1', refresh: 'refresh-1');
      final backend = FakeBackend()..profileReadApiKeyError = 'Missing or invalid API key.';
      await http.runWithClient(() async {
        await _pumpGate(tester);
        expect(find.text('Missing or invalid API key.'), findsOneWidget);
        expect(find.text('Provider sign-in'), findsNothing);
        expect(await AuthStorage.isLoggedIn(), isTrue); // nothing was thrown away
      }, backend.client);
    });

    testWidgets('signing out clears the tokens and returns to sign-in', (tester) async {
      _bigScreen(tester);
      await AuthStorage.save(access: 'access-1', refresh: 'refresh-1');
      final backend = FakeBackend()..profile = _profileJson(status: 'approved');
      await http.runWithClient(() async {
        await _pumpGate(tester);
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sign out'));
        await _settle(tester);
        expect(find.text('Provider sign-in'), findsOneWidget);
        expect(await AuthStorage.isLoggedIn(), isFalse);
      }, backend.client);
    });
  });

  group('provider icons are neutral, not repair-specific', () {
    // Tabmatch connects clients with every kind of provider, so the provider
    // side uses a briefcase rather than a hammer and screwdriver.
    testWidgets('the provider sign-in screen shows a briefcase', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ProviderSignInScreen(
          api: ApiClient(),
          idTokenProvider: () async => 'x',
          onSignedIn: (_) {},
          onSwitchRole: () {},
        ),
      ));
      expect(find.byIcon(Icons.business_center_outlined), findsOneWidget);
      expect(find.byIcon(Icons.handyman_outlined), findsNothing);
      expect(find.byIcon(Icons.handyman), findsNothing);
    });

    testWidgets('the provider card on the role screen shows a briefcase', (tester) async {
      await tester.pumpWidget(MaterialApp(home: RoleChoiceScreen(onChosen: (_) {})));
      final card = find.byKey(const Key('role-provider'));
      expect(find.descendant(of: card, matching: find.byIcon(Icons.business_center_outlined)), findsOneWidget);
      expect(find.byIcon(Icons.handyman_outlined), findsNothing);
    });

    testWidgets('the profile card lists services with a neutral icon', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProviderProfileCard(profile: ProviderProfileData.fromJson(_profileJson()))),
      ));
      expect(find.byIcon(Icons.category_outlined), findsOneWidget);
      expect(find.byIcon(Icons.handyman_outlined), findsNothing);
    });
  });

  group('signing in', () {
    testWidgets('cancelling Google sign-in shows nothing and keeps the button', (tester) async {
      final backend = FakeBackend();
      await http.runWithClient(() async {
        await _pumpGate(tester, idToken: () async => throw const SignInCancelled());
        await _signIn(tester);
        expect(find.byKey(const Key('sign-in-message')), findsNothing);
        expect(find.text('Continue with Google'), findsOneWidget);
      }, backend.client);
      expect(backend.requests, isEmpty);
    });

    testWidgets('a build without Google set up says so', (tester) async {
      final backend = FakeBackend();
      await http.runWithClient(() async {
        await _pumpGate(tester, idToken: GoogleSignInService.getIdToken);
        await _signIn(tester);
        expect(find.textContaining('not set up in this build'), findsOneWidget);
      }, backend.client);
      expect(backend.requests, isEmpty);
    });

    testWidgets('the server refusing the account (e.g. a client email) is shown', (tester) async {
      final backend = FakeBackend()
        ..signInStatus = 409
        ..signInError = 'This email already belongs to a client account. Use a different Google account.';
      await http.runWithClient(() async {
        await _pumpGate(tester);
        await _signIn(tester);
        expect(find.textContaining('already belongs to a client account'), findsOneWidget);
        expect(await AuthStorage.isLoggedIn(), isFalse);
      }, backend.client);
    });
  });

  group('ApiClient provider calls', () {
    test('a profile that does not exist yet reads as null', () async {
      final backend = FakeBackend();
      await http.runWithClient(() async {
        expect(await ApiClient().getMyProviderProfile('token'), isNull);
      }, backend.client);
    });

    test('a 401 with the API-key message is an ApiException; any other 401 is an expired session', () async {
      final keyProblem = FakeBackend()..profileReadApiKeyError = 'Missing or invalid API key.';
      await http.runWithClient(() async {
        await expectLater(
          ApiClient().getMyProviderProfile('token'),
          throwsA(isA<ApiException>().having((e) => e is SessionExpiredException, 'is SessionExpired', isFalse)),
        );
      }, keyProblem.client);

      final expired = FakeBackend()..expiredReadsBeforeSuccess = 1;
      await http.runWithClient(() async {
        await expectLater(ApiClient().getMyProviderProfile('token'), throwsA(isA<SessionExpiredException>()));
      }, expired.client);
    });

    test('profile data round-trips and never sends the status', () {
      final data = ProviderProfileData.fromJson(_profileJson(status: 'approved', note: 'ok'));
      expect(data.status, ProviderStatus.approved);
      expect(data.toJson().keys, containsAll(['business_name', 'phone', 'email', 'categories', 'cities', 'bio']));
      expect(data.toJson().containsKey('status'), isFalse);
      expect(ProviderStatus.parse('bogus'), ProviderStatus.pending);
    });
  });
}
