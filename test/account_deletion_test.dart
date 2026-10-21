import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/account/account_section.dart';
import 'package:toplinkai_app/account/delete_account.dart';
import 'package:toplinkai_app/api/api_config.dart';
import 'package:toplinkai_app/api/provider_profile.dart';
import 'package:toplinkai_app/legal/legal_pages.dart';
import 'package:toplinkai_app/pages/settings_page.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';
import 'package:toplinkai_app/provider/provider_home_screen.dart';
import 'package:toplinkai_app/provider/provider_pending_screen.dart';
import 'package:toplinkai_app/provider/provider_registration_screen.dart';
import 'package:toplinkai_app/provider/provider_session.dart';

// "Delete my account" for clients and providers, and the links to the website's legal pages.

class Server {
  Server({this.role = 'customer'});

  String role;

  /// What /accounts/delete/ answers: 200 deleted, 403 refused, 401 expired, 500 broken; or `offline`.
  int deleteStatus = 200;
  String deleteDetail = 'Staff accounts can\'t be deleted here.';
  bool offline = false;
  Completer<void>? hold;
  final requests = <http.Request>[];

  Iterable<http.Request> to(String part, {String? method}) =>
      requests.where((r) => r.url.path.contains(part) && (method == null || r.method == method));

  http.Client get client => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);
        if (path.endsWith('/accounts/token/refresh/')) return json({'detail': 'expired'}, 401);
        if (path.endsWith('/accounts/me/')) return json({'email': 'pat@example.com', 'role': role, 'full_name': 'Pat Client'});
        if (path.endsWith('/accounts/delete/') && request.method == 'POST') {
          if (offline) throw http.ClientException('no network');
          if (hold != null) await hold!.future;
          if (deleteStatus == 200) return json({'deleted': true});
          return json({'detail': deleteDetail}, deleteStatus);
        }
        if (path.endsWith('/provider/reviews/')) {
          return json({'summary': {'rating_average': null, 'review_count': 0}, 'reviews': []});
        }
        if (path.endsWith('/provider/leads/')) return json({'leads': []});
        if (path.endsWith('/conversations/')) return json({'conversations': [], 'total_unread': 0});
        return json({'detail': 'nothing here'}, 404);
      });
}

class Opened {
  final uris = <Uri>[];
  bool result = true;
  bool throws = false;

  Future<bool> call(Uri uri) async {
    if (throws) throw Exception('no browser');
    uris.add(uri);
    return result;
  }
}

void bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const profile = ProviderProfileData(
  businessName: 'Ace Plumbing',
  phone: '+17805550101',
  email: 'ace@example.com',
  categories: ['plumbing'],
  cities: ['Edmonton'],
  status: ProviderStatus.approved,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthStorage.save(access: 'tok-1', refresh: 'ref-1');
  });

  // -------------------------------------------------------------------------------------------------
  group('the website addresses', () {
    test('the site is the API\'s host without /api', () {
      expect(siteUrlFor('https://toplinkai-backend.onrender.com/api', '/privacy/'), 'https://toplinkai-backend.onrender.com/privacy/');
      expect(siteUrlFor('https://host.example/api/', '/terms/'), 'https://host.example/terms/');
      expect(siteUrlFor('http://10.0.2.2:8000/api', '/delete-account/'), 'http://10.0.2.2:8000/delete-account/');
      expect(siteUrlFor('https://host.example', 'privacy/'), 'https://host.example/privacy/');
    });

    test('every legal page has a path that exists on the website', () {
      expect({for (final p in LegalPage.values) p.path}, {'/privacy/', '/terms/', '/provider-agreement/', '/delete-account/'});
      for (final page in LegalPage.values) {
        expect(page.uri.path, page.path);
        expect(page.uri.hasScheme, isTrue);
        expect(page.title, isNotEmpty);
      }
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('opening a legal page', () {
    Future<void> pumpButton(WidgetTester tester, Opened opened) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open'),
              onPressed: () => openLegalPage(context, LegalPage.privacy, open: opened.call),
              child: const Text('open'),
            ),
          ),
        ),
      ));
    }

    testWidgets('it opens the page in the browser', (tester) async {
      final opened = Opened();
      await pumpButton(tester, opened);
      await tester.tap(find.byKey(const Key('open')));
      await settle(tester);
      expect(opened.uris.single.path, '/privacy/');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('if the phone cannot open it, the person is told', (tester) async {
      final opened = Opened()..result = false;
      await pumpButton(tester, opened);
      await tester.tap(find.byKey(const Key('open')));
      await settle(tester);
      expect(find.textContaining('Could not open Privacy Policy'), findsOneWidget);
    });

    testWidgets('an error opening it is told the same way, not thrown', (tester) async {
      final opened = Opened()..throws = true;
      await pumpButton(tester, opened);
      await tester.tap(find.byKey(const Key('open')));
      await settle(tester);
      expect(find.textContaining('Could not open Privacy Policy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('the confirmation', () {
    Future<void> pumpHost(WidgetTester tester, Server server, {bool isProvider = false, List<String>? calls}) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('start'),
              onPressed: () => startDeleteAccount(
                context,
                session: AuthSession(),
                isProvider: isProvider,
                afterDeleted: (_) async => calls?.add('left'),
              ),
              child: const Text('start'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('start')));
      await settle(tester);
    }

    Future<void> typeWord(WidgetTester tester, String word) async {
      await tester.enterText(find.byKey(const Key('delete-confirm-field')), word);
      await tester.pump();
    }

    bool confirmEnabled(WidgetTester tester) =>
        tester.widget<TextButton>(find.byKey(const Key('delete-confirm'))).onPressed != null;

    testWidgets('a client is told exactly what is deleted and what stays', (tester) async {
      final server = Server();
      await http.runWithClient(() async {
        await pumpHost(tester, server);
        expect(find.text('Delete your account?'), findsOneWidget);
        for (final item in deletedItems(isProvider: false)) {
          expect(find.text(item), findsOneWidget, reason: item);
        }
        expect(find.textContaining('Your name, email and sign-in'), findsOneWidget);
        expect(find.textContaining('The phone number, description and location on your requests'), findsOneWidget);
        expect(find.textContaining('Reviews you wrote stay, without your name'), findsOneWidget);
        expect(find.text("This can't be undone."), findsOneWidget);
      }, () => server.client);
    });

    testWidgets('a provider is told what is deleted for them', (tester) async {
      final server = Server();
      await http.runWithClient(() async {
        await pumpHost(tester, server, isProvider: true);
        for (final item in deletedItems(isProvider: true)) {
          expect(find.text(item), findsOneWidget, reason: item);
        }
        expect(find.textContaining('Your business profile'), findsOneWidget);
        expect(find.textContaining('Reviews clients wrote about you stay'), findsOneWidget);
        expect(find.textContaining('Your saved providers'), findsNothing);
      }, () => server.client);
    });

    testWidgets('the delete button stays off until DELETE is typed exactly', (tester) async {
      final server = Server();
      await http.runWithClient(() async {
        await pumpHost(tester, server);
        expect(confirmEnabled(tester), isFalse);
        for (final wrong in ['delete', 'DELET', 'DELETE ME', 'yes', '']) {
          await typeWord(tester, wrong);
          expect(confirmEnabled(tester), isFalse, reason: '"$wrong"');
        }
        await typeWord(tester, 'DELETE');
        expect(confirmEnabled(tester), isTrue);
        await typeWord(tester, 'DELETE ');
        expect(confirmEnabled(tester), isTrue, reason: 'a stray space is forgiven');
        expect(server.to('/accounts/delete/'), isEmpty);
      }, () => server.client);
    });

    testWidgets('Cancel deletes nothing and leaves nothing', (tester) async {
      final server = Server();
      final calls = <String>[];
      await http.runWithClient(() async {
        await pumpHost(tester, server, calls: calls);
        await typeWord(tester, 'DELETE');
        await tester.tap(find.byKey(const Key('delete-cancel')));
        await settle(tester);
        expect(find.text('Delete your account?'), findsNothing);
        expect(server.to('/accounts/delete/'), isEmpty);
        expect(calls, isEmpty);
        expect(await AuthStorage.isLoggedIn(), isTrue);
      }, () => server.client);
    });

    testWidgets('tapping outside the box does not close it by accident', (tester) async {
      final server = Server();
      await http.runWithClient(() async {
        await pumpHost(tester, server);
        await tester.tapAt(const Offset(5, 5));
        await settle(tester);
        expect(find.text('Delete your account?'), findsOneWidget);
      }, () => server.client);
    });

    testWidgets('confirming sends the word with the login and then leaves the app', (tester) async {
      final server = Server();
      final calls = <String>[];
      await http.runWithClient(() async {
        await pumpHost(tester, server, calls: calls);
        await typeWord(tester, 'DELETE');
        await tester.tap(find.byKey(const Key('delete-confirm')));
        await settle(tester);

        final post = server.to('/accounts/delete/', method: 'POST').single;
        expect(jsonDecode(post.body), {'confirm': 'DELETE'});
        expect(post.headers['Authorization'], 'Bearer tok-1');
        expect(find.text('Delete your account?'), findsNothing);
        expect(calls, ['left']);
      }, () => server.client);
    });

    testWidgets('while it is being deleted nothing can be tapped twice', (tester) async {
      final server = Server()..hold = Completer<void>();
      await http.runWithClient(() async {
        await pumpHost(tester, server);
        await typeWord(tester, 'DELETE');
        await tester.tap(find.byKey(const Key('delete-confirm')));
        await tester.pump();
        expect(confirmEnabled(tester), isFalse);
        expect(tester.widget<TextButton>(find.byKey(const Key('delete-cancel'))).onPressed, isNull);
        expect(tester.widget<TextField>(find.byKey(const Key('delete-confirm-field'))).enabled, isFalse);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        server.hold!.complete();
        await settle(tester);
        expect(server.to('/accounts/delete/'), hasLength(1));
      }, () => server.client);
    });

    testWidgets('a refusal from the server is shown and nothing is left', (tester) async {
      final server = Server()
        ..deleteStatus = 403
        ..deleteDetail = "Staff accounts can't be deleted here.";
      final calls = <String>[];
      await http.runWithClient(() async {
        await pumpHost(tester, server, calls: calls);
        await typeWord(tester, 'DELETE');
        await tester.tap(find.byKey(const Key('delete-confirm')));
        await settle(tester);
        expect(find.text("Staff accounts can't be deleted here."), findsOneWidget);
        expect(find.text('Delete your account?'), findsOneWidget);
        expect(confirmEnabled(tester), isTrue);
        expect(calls, isEmpty);
        expect(await AuthStorage.isLoggedIn(), isTrue);
      }, () => server.client);
    });

    testWidgets('with no connection it says so and can be tried again', (tester) async {
      final server = Server()..offline = true;
      final calls = <String>[];
      await http.runWithClient(() async {
        await pumpHost(tester, server, calls: calls);
        await typeWord(tester, 'DELETE');
        await tester.tap(find.byKey(const Key('delete-confirm')));
        await settle(tester);
        expect(find.textContaining('Could not reach the server'), findsOneWidget);
        expect(confirmEnabled(tester), isTrue);
        expect(calls, isEmpty);
      }, () => server.client);
    });

    testWidgets('an expired login is explained, not treated as deleted', (tester) async {
      final server = Server()..deleteStatus = 401;
      final calls = <String>[];
      await http.runWithClient(() async {
        await pumpHost(tester, server, calls: calls);
        await typeWord(tester, 'DELETE');
        await tester.tap(find.byKey(const Key('delete-confirm')));
        await settle(tester);
        expect(find.textContaining('Your session has expired'), findsOneWidget);
        expect(calls, isEmpty);
      }, () => server.client);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('clients: Settings', () {
    Future<void> pumpSettings(WidgetTester tester, Server server, Opened opened, List<String> calls) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SettingsBody(openUrl: opened.call, afterDeleted: (_) async => calls.add('left'))),
      ));
      await settle(tester);
    }

    testWidgets('a signed-in client has Delete my account, in red', (tester) async {
      final server = Server();
      await http.runWithClient(() async {
        await pumpSettings(tester, server, Opened(), []);
        expect(find.byKey(const Key('delete-account')), findsOneWidget);
        expect(find.text('Delete my account'), findsOneWidget);
        final label = tester.widget<Text>(find.text('Delete my account'));
        expect(label.style!.color, const Color(0xFFBA1A1A));
      }, () => server.client);
    });

    testWidgets('someone who is not signed in has nothing to delete', (tester) async {
      await AuthStorage.clear();
      final server = Server();
      await http.runWithClient(() async {
        await pumpSettings(tester, server, Opened(), []);
        expect(find.byKey(const Key('delete-account')), findsNothing);
        expect(find.text('Delete my account'), findsNothing);
      }, () => server.client);
    });

    testWidgets('it asks first, deletes, and leaves', (tester) async {
      final server = Server();
      final calls = <String>[];
      await http.runWithClient(() async {
        await pumpSettings(tester, server, Opened(), calls);
        await tester.tap(find.byKey(const Key('delete-account')));
        await settle(tester);
        expect(find.text('Delete your account?'), findsOneWidget);
        expect(find.text('Your saved providers'), findsOneWidget);
        expect(server.to('/accounts/delete/'), isEmpty);
        await tester.enterText(find.byKey(const Key('delete-confirm-field')), 'DELETE');
        await tester.pump();
        await tester.tap(find.byKey(const Key('delete-confirm')));
        await settle(tester);
        expect(server.to('/accounts/delete/', method: 'POST'), hasLength(1));
        expect(calls, ['left']);
      }, () => server.client);
    });

    testWidgets('Privacy Policy and Terms of Service open the website pages', (tester) async {
      final server = Server();
      final opened = Opened();
      await http.runWithClient(() async {
        await pumpSettings(tester, server, opened, []);
        await tester.tap(find.byKey(const Key('link-privacy')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('link-terms')));
        await settle(tester);
        expect(opened.uris.map((u) => u.path), ['/privacy/', '/terms/']);
        expect(opened.uris.first.toString(), ApiConfig.siteUrl('/privacy/'));
        expect(find.textContaining('coming soon'), findsNothing);
      }, () => server.client);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('providers', () {
    testWidgets('the account section has the three legal pages and Delete my account', (tester) async {
      bigScreen(tester);
      final opened = Opened();
      final calls = <String>[];
      final server = Server(role: 'provider');
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountAndLegalSection(session: AuthSession(), openUrl: opened.call, afterDeleted: (_) async => calls.add('left')),
            ),
          ),
        ));
        for (final key in ['link-privacy', 'link-terms', 'link-provider-agreement']) {
          await tester.tap(find.byKey(Key(key)));
          await settle(tester);
        }
        expect(opened.uris.map((u) => u.path), ['/privacy/', '/terms/', '/provider-agreement/']);

        await tester.tap(find.byKey(const Key('delete-account')));
        await settle(tester);
        expect(find.text('Your business profile: name, phone, email, description, services and cities'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('delete-confirm-field')), 'DELETE');
        await tester.pump();
        await tester.tap(find.byKey(const Key('delete-confirm')));
        await settle(tester);
        expect(server.to('/accounts/delete/', method: 'POST'), hasLength(1));
        expect(calls, ['left']);
      }, () => server.client);
    });

    testWidgets('an approved provider finds it on their Profile tab', (tester) async {
      bigScreen(tester);
      final server = Server(role: 'provider');
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: ProviderHomeScreen(
            profile: profile,
            session: AuthSession(),
            onEdit: () {},
            onRefresh: () async {},
            onSignOut: () {},
            onSwitchRole: () {},
            onSessionExpired: () {},
          ),
        ));
        await settle(tester);
        expect(find.text('Account and legal'), findsOneWidget);
        expect(find.byKey(const Key('delete-account')), findsOneWidget);
      }, () => server.client);
    });

    testWidgets('a provider waiting for approval can delete too', (tester) async {
      bigScreen(tester);
      final server = Server(role: 'provider');
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: ProviderPendingScreen(
            profile: const ProviderProfileData(
              businessName: 'New Co',
              phone: '+17805550102',
              email: 'new@example.com',
              categories: ['plumbing'],
              cities: ['Edmonton'],
            ),
            session: AuthSession(),
            onRefresh: () async {},
            onEdit: () {},
            onSignOut: () {},
            onSwitchRole: () {},
          ),
        ));
        await settle(tester);
        expect(find.byKey(const Key('delete-account')), findsOneWidget);
        expect(find.byKey(const Key('link-privacy')), findsOneWidget);
      }, () => server.client);
    });

    testWidgets('a provider filling in the registration form can delete the account they just created', (tester) async {
      bigScreen(tester);
      final server = Server(role: 'provider');
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: ProviderRegistrationScreen(
            session: AuthSession(),
            defaultEmail: 'pro@example.com',
            onSaved: (_) {},
            onSessionExpired: () {},
          ),
        ));
        await settle(tester);
        expect(find.byKey(const Key('delete-account')), findsOneWidget);
        expect(find.byKey(const Key('link-provider-agreement')), findsOneWidget);
      }, () => server.client);
    });
  });
}
