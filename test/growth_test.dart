import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/api_client.dart';
import 'package:toplinkai_app/api/growth.dart';
import 'package:toplinkai_app/api/reviews.dart';
import 'package:toplinkai_app/api/service_request.dart';
import 'package:toplinkai_app/growth/growth_links.dart';
import 'package:toplinkai_app/growth/share_provider.dart';
import 'package:toplinkai_app/home/home_screen.dart';
import 'package:toplinkai_app/onboarding/onboarding_screen.dart';
import 'package:toplinkai_app/pages/settings_page.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';
import 'package:toplinkai_app/provider/provider_session.dart';

// Growth: links into the app (website, invites, reminders), sharing a provider, "Book again", and the
// Settings switches for reminders and invites.

class Server {
  final requests = <http.Request>[];
  bool seasonal = true;
  int claimStatus = 201;
  bool offline = false;

  Iterable<http.Request> to(String part, {String? method}) =>
      requests.where((r) => r.url.path.contains(part) && (method == null || r.method == method));

  http.Client get client => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);
        if (offline) throw http.ClientException('no network');
        if (path.endsWith('/accounts/me/')) return json({'email': 'pat@example.com', 'role': 'customer', 'full_name': 'Pat Client'});
        if (path.endsWith('/growth/invite/')) {
          return json({
            'code': 'ABCD2345',
            'url': 'https://tabmatch.example/invite/ABCD2345/',
            'share_text': 'Join with my link: https://tabmatch.example/invite/ABCD2345/',
            'signups': 2,
          });
        }
        if (path.endsWith('/growth/invite/claim/')) {
          return claimStatus == 201 ? json({'claimed': true}, 201) : json({'detail': 'That invite code isn\'t valid.'}, claimStatus);
        }
        if (path.endsWith('/growth/reminders/')) {
          if (request.method == 'PATCH') seasonal = (jsonDecode(request.body) as Map)['seasonal_reminders'] as bool;
          return json({'seasonal_reminders': seasonal});
        }
        return json({'detail': 'nothing here'}, 404);
      });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ServiceRequestRecord completedRequest({Review? review}) => ServiceRequestRecord(
      id: 7,
      category: 'hvac',
      city: 'Edmonton',
      problemDescription: '',
      phone: '+17805550199',
      status: 'new',
      createdAt: DateTime(2026, 9, 1),
      acceptedOffers: [
        AcceptedOffer(offerId: 11, providerId: 5, providerName: 'Ace Heating', hired: true, jobCompleted: true, review: review),
      ],
    );

final review = Review(id: 1, rating: 5, clientName: 'Pat C.', createdAt: DateTime(2026, 9, 2), mine: true);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthStorage.save(access: 'tok-1', refresh: 'ref-1');
  });

  group('links into the app', () {
    test('a request link from an SEO page or reminder', () {
      final link = parseGrowthLink('/request?service=hvac&src=seasonal&ref=furnace-check') as RequestLink;
      expect(link.service, 'hvac');
      expect(link.attribution, const RequestAttribution(source: 'seasonal', ref: 'furnace-check'));

      final full = parseGrowthLink('tabmatch://open/request?service=plumbing&src=seo&ref=windermere') as RequestLink;
      expect(full.service, 'plumbing');
      expect(full.attribution, const RequestAttribution(source: 'seo', ref: 'windermere'));
    });

    test('unknown sources and unsafe refs are dropped, the service is kept', () {
      final noSource = parseGrowthLink('/request?service=hvac&src=billboard&ref=x') as RequestLink;
      expect(noSource.attribution, isNull);
      final badRef = parseGrowthLink('/request?service=hvac&src=seo&ref=%3Cscript%3E') as RequestLink;
      expect(badRef.attribution, const RequestAttribution(source: 'seo'));
    });

    test('an invite link', () {
      final link = parseGrowthLink('/invite?code=abcd2345&provider=5') as InviteLink;
      expect(link.code, 'ABCD2345');
      expect(link.providerId, 5);
      expect((parseGrowthLink('tabmatch://open/invite?code=ABCD2345') as InviteLink).providerId, isNull);
    });

    test('anything else is not a growth link', () {
      for (final route in [null, '', '/', '/request', '/request?service=', '/settings', 'https://evil.example/request?service=hvac',
          'tabmatch://other/request?service=hvac', '/invite', '/request?service=../../x']) {
        expect(parseGrowthLink(route), isNull, reason: '$route');
      }
    });

    test("a seasonal reminder's push opens the request flow", () {
      final link = requestLinkFromPush({'type': 'request_prefill', 'service': 'hvac', 'source': 'seasonal', 'ref': 'furnace-check'})!;
      expect(link.service, 'hvac');
      expect(link.attribution, const RequestAttribution(source: 'seasonal', ref: 'furnace-check'));
      expect(requestLinkFromPush({'type': 'chat', 'conversation_id': '3'}), isNull);
      expect(requestLinkFromPush({'type': 'request_prefill', 'service': 'a/b'}), isNull);
    });

    test('only growth links get a route', () {
      expect(growthRoute(const RouteSettings(name: '/request?service=hvac')), isNotNull);
      expect(growthRoute(const RouteSettings(name: '/somewhere')), isNull);
    });

    testWidgets('a request link opens the request flow with the service chosen', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(onGenerateRoute: growthRoute, initialRoute: '/request?service=plumbing&src=seo&ref=windermere'));
      await settle(tester);
      final screen = tester.widget<OnboardingScreen>(find.byType(OnboardingScreen));
      expect(screen.initialCategory?.slug, 'plumbing');
      expect(screen.attribution, const RequestAttribution(source: 'seo', ref: 'windermere'));
    });

    testWidgets('an invite link welcomes them and keeps the code for sign-in', (tester) async {
      await tester.pumpWidget(MaterialApp(onGenerateRoute: growthRoute, initialRoute: '/invite?code=ABCD2345&provider=5'));
      await settle(tester);
      expect(find.byKey(const Key('invite-welcome-text')), findsOneWidget);
      final pending = await PendingInvite.load();
      expect(pending?.code, 'ABCD2345');
      expect(pending?.providerId, 5);
    });
  });

  group('recording an invite', () {
    test('a waiting invite is recorded after sign-in, then forgotten', () async {
      final server = Server();
      await PendingInvite.save('ABCD2345', providerId: 5);
      final recorded = await http.runWithClient(() => claimPendingInvite(AuthSession()), () => server.client);
      expect(recorded, isTrue);
      final body = jsonDecode(server.to('/growth/invite/claim/').single.body) as Map;
      expect(body, {'code': 'ABCD2345', 'provider_id': 5});
      expect(await PendingInvite.load(), isNull);
    });

    test('a code the server refuses is dropped; a network problem keeps it for next time', () async {
      final server = Server()..claimStatus = 409;
      await PendingInvite.save('ABCD2345');
      expect(await http.runWithClient(() => claimPendingInvite(AuthSession()), () => server.client), isFalse);
      expect(await PendingInvite.load(), isNull);

      server.offline = true;
      await PendingInvite.save('ABCD2345');
      expect(await http.runWithClient(() => claimPendingInvite(AuthSession()), () => server.client), isFalse);
      expect((await PendingInvite.load())?.code, 'ABCD2345');
    });

    test('a request is sent with where it came from', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'request_id': 1, 'status': 'new'}), 201);
      });
      await http.runWithClient(
        () => ApiClient().createServiceRequest(
          accessToken: 't',
          category: 'hvac',
          phone: '+17805550199',
          consent: true,
          attribution: const RequestAttribution(source: 'seasonal', ref: 'furnace-check'),
        ),
        () => client,
      );
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['source'], 'seasonal');
      expect(body['source_ref'], 'furnace-check');

      requests.clear();
      await http.runWithClient(
        () => ApiClient().createServiceRequest(accessToken: 't', category: 'hvac', phone: '+17805550199', consent: true),
        () => client,
      );
      expect((jsonDecode(requests.single.body) as Map).containsKey('source'), isFalse);
    });
  });

  group('sharing a provider', () {
    test('the share link is the invite with the provider on it', () {
      const invite = InviteInfo(code: 'ABCD2345', url: 'https://tabmatch.example/invite/ABCD2345/', shareText: '');
      expect(invite.providerUrl(5), 'https://tabmatch.example/invite/ABCD2345/?provider=5');
      final text = providerShareText(providerName: 'Ace Heating', serviceLabel: 'HVAC', url: invite.providerUrl(5));
      expect(text, contains('Ace Heating'));
      expect(text, endsWith('https://tabmatch.example/invite/ABCD2345/?provider=5'));
    });

    test('WhatsApp and text message links carry the message', () {
      const text = 'Try Ace & Co: https://x.example/?a=1';
      final wa = whatsAppShareUri(text);
      expect(wa.host, 'wa.me');
      expect(wa.queryParameters['text'], text);
      expect(smsShareUri(text, platform: TargetPlatform.android).toString(), startsWith('sms:?body='));
      expect(smsShareUri(text, platform: TargetPlatform.iOS).toString(), startsWith('sms:&body='));
      expect(Uri.decodeComponent(smsShareUri(text, platform: TargetPlatform.android).toString().split('body=')[1]), text);
    });

    testWidgets('Share and Book again show once the job is complete and reviewed', (tester) async {
      bigScreen(tester);
      final shared = <int>[];
      final rebooked = <int>[];
      Future<void> show(ServiceRequestRecord r) => tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: ServiceRequestCard(request: r, onShare: (o) => shared.add(o.offerId), onBookAgain: (o) => rebooked.add(o.offerId)),
            ),
          ));

      await show(completedRequest());
      expect(find.byKey(const Key('share-provider-11')), findsNothing);
      expect(find.byKey(const Key('book-again-11')), findsNothing);

      await show(completedRequest(review: review));
      await tester.tap(find.byKey(const Key('share-provider-11')));
      await tester.tap(find.byKey(const Key('book-again-11')));
      expect(shared, [11]);
      expect(rebooked, [11]);
    });

    testWidgets('the share sheet offers WhatsApp, a text and copying the link', (tester) async {
      bigScreen(tester);
      final server = Server();
      final opened = <Uri>[];
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShareProviderSheet(
                  context,
                  session: AuthSession(),
                  providerId: 5,
                  providerName: 'Ace Heating',
                  serviceLabel: 'HVAC',
                  launcher: (uri) async {
                    opened.add(uri);
                    return true;
                  },
                ),
                child: const Text('share'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('share'));
        await settle(tester);
        expect(find.text('Share Ace Heating'), findsOneWidget);
        await tester.tap(find.byKey(const Key('share-whatsapp')));
        await settle(tester);
        expect(opened.single.host, 'wa.me');
        expect(opened.single.queryParameters['text'], contains('/invite/ABCD2345/?provider=5'));

        await tester.tap(find.text('share'));
        await settle(tester);
        await tester.tap(find.byKey(const Key('share-copy')));
        await settle(tester);
        expect(copied, 'https://tabmatch.example/invite/ABCD2345/?provider=5');
        expect(find.text('Link copied.'), findsOneWidget);
      }, () => server.client);
    });
  });

  group('Settings', () {
    testWidgets('a client can turn seasonal reminders off and share their invite', (tester) async {
      bigScreen(tester);
      final server = Server();
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SettingsBody())));
        await settle(tester);
        expect(find.byKey(const Key('seasonal-reminders')), findsOneWidget);
        await tester.tap(find.byKey(const Key('seasonal-reminders')));
        await settle(tester);
        expect(jsonDecode(server.to('/growth/reminders/', method: 'PATCH').single.body), {'seasonal_reminders': false});
        expect(tester.widget<Switch>(find.descendant(of: find.byKey(const Key('seasonal-reminders')), matching: find.byType(Switch))).value, isFalse);

        await tester.tap(find.byKey(const Key('invite-friends')));
        await settle(tester);
        expect(find.textContaining('Your invite code is ABCD2345. 2 friends have joined with it.'), findsOneWidget);
      }, () => server.client);
    });

    testWidgets("a friend's code can be typed in", (tester) async {
      bigScreen(tester);
      final server = Server();
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SettingsBody())));
        await settle(tester);
        await tester.tap(find.byKey(const Key('enter-invite-code')));
        await settle(tester);
        await tester.enterText(find.byKey(const Key('invite-code-field')), 'abcd2345');
        await tester.tap(find.byKey(const Key('invite-code-submit')));
        await settle(tester);
        expect(jsonDecode(server.to('/growth/invite/claim/').single.body), {'code': 'ABCD2345'});
        expect(find.text("Thanks! Your friend's invite is recorded."), findsOneWidget);
      }, () => server.client);
    });
  });

  test('Android and iOS builds open tabmatch:// links', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('<data android:scheme="tabmatch" android:host="open"/>'));
    expect(manifest, contains('android:name="flutter_deeplinking_enabled" android:value="true"'));
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>CFBundleURLSchemes</key>'));
    expect(plist, contains('<string>tabmatch</string>'));
  });
}
