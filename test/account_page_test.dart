import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/api_client.dart';
import 'package:toplinkai_app/api/auth_models.dart';
import 'package:toplinkai_app/pages/account_page.dart';
import 'package:toplinkai_app/pages/settings_page.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';

// Settings -> Account (previously a "coming soon" stub) plus the Log out row
// that used to leave the stored session in place.

class _FakeApi extends ApiClient {
  _FakeApi({this.getMeResult, this.getMeError, this.updateError});

  AccountProfile? getMeResult;
  Object? getMeError;
  Object? updateError;

  int getMeCalls = 0;
  final updates = <({String? fullName, String? email})>[];

  @override
  Future<AccountProfile> getMe(String accessToken) async {
    getMeCalls++;
    if (getMeError != null) throw getMeError!;
    return getMeResult!;
  }

  @override
  Future<AccountProfile> updateMe({required String accessToken, String? fullName, String? email}) async {
    updates.add((fullName: fullName, email: email));
    if (updateError != null) throw updateError!;
    final current = getMeResult!;
    return AccountProfile(
      email: email ?? current.email,
      role: current.role,
      fullName: fullName ?? current.fullName,
      providerProfile: null,
    );
  }
}

const _customer = AccountProfile(
  email: 'olive@example.com',
  role: UserRole.customer,
  fullName: 'Olive Owner',
  providerProfile: null,
);

void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpAccount(WidgetTester tester, _FakeApi api) async {
  useTallScreen(tester);
  await tester.pumpWidget(MaterialApp(home: AccountPage(apiClient: api)));
  await tester.pumpAndSettle();
}

Future<void> signIn() => AuthStorage.save(access: 'access-token', refresh: 'refresh-token');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('AccountPage', () {
    testWidgets('with no account it says so plainly and offers business login', (tester) async {
      await _pumpAccount(tester, _FakeApi());

      expect(find.text("You're browsing without an account"), findsOneWidget);
      expect(find.text('Log in or create a business account'), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // nothing to edit
    });

    testWidgets('a signed-in user sees their details, and Save stays disabled until something changes', (tester) async {
      await signIn();
      await _pumpAccount(tester, _FakeApi(getMeResult: _customer));

      expect(find.text('Customer account'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Olive Owner'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'olive@example.com'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Olive Owner'), 'Olive Q. Owner');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNotNull);
    });

    testWidgets('a business account is labelled as one', (tester) async {
      await signIn();
      await _pumpAccount(
        tester,
        _FakeApi(getMeResult: const AccountProfile(email: 'pro@example.com', role: UserRole.provider, fullName: 'Pat', providerProfile: null)),
      );
      expect(find.text('Business account'), findsOneWidget);
    });

    testWidgets('saving a name change sends only the name', (tester) async {
      await signIn();
      final api = _FakeApi(getMeResult: _customer);
      await _pumpAccount(tester, api);

      await tester.enterText(find.widgetWithText(TextField, 'Olive Owner'), '  Olive Q. Owner ');
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(api.updates, [(fullName: 'Olive Q. Owner', email: null)]);
      expect(find.text('Account updated.'), findsOneWidget);
    });

    testWidgets('saving an email change sends only the email', (tester) async {
      await signIn();
      final api = _FakeApi(getMeResult: _customer);
      await _pumpAccount(tester, api);

      await tester.enterText(find.widgetWithText(TextField, 'olive@example.com'), 'new@example.com');
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(api.updates, [(fullName: null, email: 'new@example.com')]);
    });

    testWidgets('an obviously invalid email is caught before any request is made', (tester) async {
      await signIn();
      final api = _FakeApi(getMeResult: _customer);
      await _pumpAccount(tester, api);

      await tester.enterText(find.widgetWithText(TextField, 'olive@example.com'), 'not-an-email');
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(api.updates, isEmpty);
    });

    testWidgets("the server's reason (email already in use) is shown inline and the edit is kept", (tester) async {
      await signIn();
      final api = _FakeApi(getMeResult: _customer, updateError: ApiException('An account with this email already exists.'));
      await _pumpAccount(tester, api);

      await tester.enterText(find.widgetWithText(TextField, 'olive@example.com'), 'taken@example.com');
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('An account with this email already exists.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'taken@example.com'), findsOneWidget);
    });

    testWidgets('an expired session says so instead of offering a Retry that cannot work', (tester) async {
      await signIn();
      await _pumpAccount(tester, _FakeApi(getMeError: SessionExpiredException()));

      expect(find.text('Your session has expired'), findsOneWidget);
      expect(find.text('Log in again'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('an expired session found while saving also routes to log-in', (tester) async {
      await signIn();
      final api = _FakeApi(getMeResult: _customer, updateError: SessionExpiredException());
      await _pumpAccount(tester, api);

      await tester.enterText(find.widgetWithText(TextField, 'Olive Owner'), 'New Name');
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Your session has expired'), findsOneWidget);
    });

    testWidgets('"Log in again" clears the dead session first', (tester) async {
      await signIn();
      await _pumpAccount(tester, _FakeApi(getMeError: SessionExpiredException()));

      await tester.tap(find.text('Log in again'));
      await tester.pumpAndSettle();

      expect(await AuthStorage.isLoggedIn(), isFalse);
    });

    testWidgets('a network failure offers Retry, which reloads', (tester) async {
      await signIn();
      final api = _FakeApi(getMeError: ApiException('Could not load your account (500).'));
      await _pumpAccount(tester, api);

      expect(find.text("Couldn't load your account"), findsOneWidget);
      expect(find.text('Could not load your account (500).'), findsOneWidget);

      api.getMeError = null;
      api.getMeResult = _customer;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.getMeCalls, 2);
      expect(find.widgetWithText(TextField, 'olive@example.com'), findsOneWidget);
    });
  });

  group('Settings', () {
    testWidgets('the Account row opens the Account screen instead of a "coming soon" note', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit profile and email'));
      await tester.pumpAndSettle();

      expect(find.text('Account editing is coming soon.'), findsNothing);
      expect(find.byType(AccountPage), findsOneWidget);
    });

    testWidgets('Log out actually ends the stored session', (tester) async {
      await signIn();
      expect(await AuthStorage.isLoggedIn(), isTrue);

      useTallScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SettingsBody())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pump(const Duration(seconds: 1));

      expect(await AuthStorage.isLoggedIn(), isFalse);
    });
  });
}
