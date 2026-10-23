import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/api_client.dart';
import 'package:toplinkai_app/api/provider_profile.dart';
import 'package:toplinkai_app/client/client_sign_in_screen.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';
import 'package:toplinkai_app/provider/provider_sign_in_screen.dart';
import 'package:toplinkai_app/provider/provider_widgets.dart';

// "Continue with email": a 6-digit code instead of Google (accounts.email_login on the server).

class Server {
  bool enabled = true;
  String goodCode = '123456';
  final requests = <http.Request>[];

  Iterable<http.Request> to(String part) => requests.where((r) => r.url.path.contains(part));

  http.Client get client => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);
        if (path.endsWith('/accounts/email/status/')) return json({'enabled': enabled});
        if (path.endsWith('/accounts/email/start/')) {
          return json({'detail': 'If that address can receive email, a 6-digit code is on its way.'});
        }
        if (path.endsWith('/accounts/email/verify/')) {
          final body = jsonDecode(request.body) as Map;
          if (body['code'] != goodCode) return json({'detail': 'That code is wrong or has expired.'}, 400);
          return json({
            'access': 'acc-email',
            'refresh': 'ref-email',
            'email': body['email'],
            'full_name': '',
            'is_new_account': true,
            if (body['role'] == 'provider') 'profile': null,
          });
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
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A page with a button that opens the client sign-in screen and records what it closed with.
Widget clientHost(List<bool?> results) => MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => ClientSignInScreen(api: ApiClient(), idTokenProvider: () async => 'x')),
              )),
          child: const Text('open'),
        ),
      ),
    );

Future<void> signInWithCode(WidgetTester tester, {required String email, required String code}) async {
  await tester.enterText(find.byKey(const Key('email-sign-in-email')), email);
  await tester.pump();
  await tester.tap(find.byKey(const Key('email-sign-in-send')));
  await settle(tester);
  await tester.enterText(find.byKey(const Key('email-sign-in-code')), code);
  await tester.pump();
  await tester.tap(find.byKey(const Key('email-sign-in-verify')));
  await settle(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('the email option is hidden when the server cannot send codes', (tester) async {
    bigScreen(tester);
    final server = Server()..enabled = false;
    await http.runWithClient(() async {
      await tester.pumpWidget(clientHost([]));
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.byKey(const Key('client-google-sign-in')), findsOneWidget);
      expect(find.byKey(const Key('client-email-sign-in')), findsNothing);
    }, () => server.client);
  });

  testWidgets('a client signs in with an emailed code', (tester) async {
    bigScreen(tester);
    final server = Server();
    final results = <bool?>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(clientHost(results));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('client-email-sign-in')));
      await settle(tester);

      // The send button waits for something that looks like an email.
      await tester.enterText(find.byKey(const Key('email-sign-in-email')), 'not-an-email');
      await tester.pump();
      expect(tester.widget<BrandButton>(find.byKey(const Key('email-sign-in-send'))).onPressed, isNull);

      await signInWithCode(tester, email: ' Pat@Example.com ', code: '123456');
      expect(jsonDecode(server.to('/email/start/').single.body), {'email': 'pat@example.com', 'role': 'customer'});
      expect(jsonDecode(server.to('/email/verify/').single.body), {'email': 'pat@example.com', 'role': 'customer', 'code': '123456'});
      expect(results, [true]);
      expect(await AuthStorage.getAccessToken(), 'acc-email');
    }, () => server.client);
  });

  testWidgets('a wrong code shows the error and lets them try again', (tester) async {
    bigScreen(tester);
    final server = Server();
    final results = <bool?>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(clientHost(results));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('client-email-sign-in')));
      await settle(tester);
      await signInWithCode(tester, email: 'pat@example.com', code: '999999');
      expect(find.text('That code is wrong or has expired.'), findsOneWidget);
      expect(results, isEmpty);
      expect(await AuthStorage.getAccessToken(), isNull);

      await tester.enterText(find.byKey(const Key('email-sign-in-code')), '123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('email-sign-in-verify')));
      await settle(tester);
      expect(results, [true]);
    }, () => server.client);
  });

  testWidgets('a provider signs in with an emailed code', (tester) async {
    bigScreen(tester);
    final server = Server();
    final signedIn = <ProviderSignIn>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: ProviderSignInScreen(
          api: ApiClient(),
          idTokenProvider: () async => 'x',
          onSignedIn: signedIn.add,
          onSwitchRole: () {},
        ),
      ));
      await settle(tester);
      await tester.tap(find.byKey(const Key('provider-email-sign-in')));
      await settle(tester);
      await signInWithCode(tester, email: 'ace@example.com', code: '123456');
      expect((jsonDecode(server.to('/email/verify/').single.body) as Map)['role'], 'provider');
      expect(signedIn.single.email, 'ace@example.com');
      expect(signedIn.single.profile, isNull);
      expect(await AuthStorage.getAccessToken(), 'acc-email');
    }, () => server.client);
  });

  test('the status check never throws: a broken server just hides the option', () async {
    final failing = MockClient((_) async => throw http.ClientException('offline'));
    expect(await http.runWithClient(() => ApiClient().emailSignInEnabled(), () => failing), isFalse);
  });
}
