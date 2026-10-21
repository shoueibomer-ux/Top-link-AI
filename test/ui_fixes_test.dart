import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/service_request.dart';
import 'package:toplinkai_app/home/home_screen.dart';
import 'package:toplinkai_app/messaging/push_service.dart';
import 'package:toplinkai_app/onboarding/location_step.dart';
import 'package:toplinkai_app/onboarding/location_validation.dart';
import 'package:toplinkai_app/onboarding/onboarding_screen.dart';
import 'package:toplinkai_app/onboarding/phone_validation.dart';
import 'package:toplinkai_app/onboarding/service_category.dart';
import 'package:toplinkai_app/pages/settings_page.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';
import 'package:toplinkai_app/role/role_choice_screen.dart';
import 'package:toplinkai_app/widgets/app_drawer.dart';

// The fixes from the visual review: phone formatting, the location step, History cards, the role screen, the
// client menu, the Settings notifications switch and account card, and when notifications are asked for.

class FakePush implements PushBackend {
  FakePush({this.configured = true, this.granted = true, this.grantWhenAsked = true});

  final bool configured;
  bool granted;
  final bool grantWhenAsked;
  int prompts = 0;
  final refresh = StreamController<String>.broadcast();

  @override
  Future<bool> init() async => configured;

  @override
  Future<void> requestPermission() async {
    prompts++;
    if (grantWhenAsked) granted = true;
  }

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<String?> token() async => 'phone-token';

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get onOpenedFromNotification => const Stream.empty();

  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;

  @override
  Future<void> deleteToken() async {}
}

/// A server that records everything and answers the few endpoints these screens use.
class Server {
  final requests = <http.Request>[];
  Map<String, dynamic>? me = {'email': 'pat@example.com', 'role': 'customer', 'full_name': 'Pat Client'};

  Iterable<http.Request> to(String part, {String? method}) =>
      requests.where((r) => r.url.path.contains(part) && (method == null || r.method == method));

  http.Client get client => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);
        if (path.endsWith('/accounts/me/')) return me == null ? json({'detail': 'no'}, 401) : json(me!);
        if (path.endsWith('/devices/')) return json({'registered': request.method == 'POST'});
        if (path.endsWith('/requests/') && request.method == 'POST') return json({'request_id': 7, 'status': 'new'}, 201);
        if (path.endsWith('/requests/mine/')) return json({'requests': []});
        if (path.endsWith('/conversations/')) return json({'conversations': [], 'total_unread': 0});
        return json({'detail': 'nothing here'}, 404);
      });
}

void bigScreen(WidgetTester tester, {Size size = const Size(1080, 2400)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, dynamic> offerJson({bool completed = false, int id = 42, String name = 'Ace Plumbing'}) => {
      'offer_id': id,
      'provider': {'id': id, 'business_name': name},
      'hired': completed,
      'job_completed': completed,
      'can_complete': !completed,
      'can_review': completed,
    };

ServiceRequestRecord requestRecord({
  String category = 'plumbing',
  String status = 'new',
  String urgency = 'today',
  List<Map<String, dynamic>> accepted = const [],
}) =>
    ServiceRequestRecord.fromJson({
      'id': 7,
      'category': category,
      'city': 'Edmonton',
      'problem_description': '',
      'phone': '+17805550100',
      'status': status,
      'urgency': urgency,
      'created_at': '2026-10-10T12:00:00Z',
      'accepted_offers': accepted,
    });

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthStorage.save(access: 'tok-1', refresh: 'ref-1');
    resetCatalogForTests();
  });

  tearDown(() {
    PushService.instance.disposeForTest();
    PushService.instance = PushService();
  });

  // -------------------------------------------------------------------------------------------------
  group('phone numbers read the way people write them', () {
    TextEditingValue typed(String text, [String before = '']) =>
        const PhoneInputFormatter().formatEditUpdate(TextEditingValue(text: before), TextEditingValue(text: text));

    test('formatPhone shows a stored number as (780) 555-0100', () {
      expect(formatPhone('+17805550100'), '(780) 555-0100');
      expect(formatPhone('780-555-0100'), '(780) 555-0100');
      expect(formatPhone('1 (780) 555 0100'), '(780) 555-0100');
    });

    test('formatPhone leaves anything that is not a North American number alone', () {
      expect(formatPhone('+442079460958'), '+442079460958');
      expect(formatPhone('abc'), 'abc');
      expect(formatPhone(''), '');
    });

    test('typing is formatted as it goes', () {
      expect(typed('7').text, '(7');
      expect(typed('780').text, '(780');
      expect(typed('7805').text, '(780) 5');
      expect(typed('7805550').text, '(780) 555-0');
      expect(typed('7805550100').text, '(780) 555-0100');
    });

    test('a leading country code 1 is dropped', () {
      expect(typed('17805550100').text, '(780) 555-0100');
      expect(typed('+1 780 555 0100').text, '(780) 555-0100');
    });

    test('the formatted number is still read as the same number', () {
      expect(normalizeNorthAmericanPhone(typed('7805550100').text), '+17805550100');
      expect(normalizeNorthAmericanPhone('(780) 555-0100'), '+17805550100');
    });

    test('too many digits are left as typed so the form can say it is wrong, never cut short', () {
      expect(typed('58792199587').text, '58792199587');
      expect(normalizeNorthAmericanPhone(typed('58792199587').text), isNull);
      expect(typed('+44 20 7946 0958').text, '+44 20 7946 0958');
    });

    test('backspace removes a digit even when it lands on a bracket, space or dash', () {
      expect(typed('(780) 5550100', '(780) 555-0100').text, '(780) 555-010'); // the dash was deleted
      expect(typed('(780)5', '(780) 5').text, '(780'); // the space was deleted, so the 5 goes
      expect(typed('', '(7').text, '');
    });

    test('empty stays empty', () {
      expect(typed('').text, '');
      expect(typed('abc').text, '');
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('where the job is', () {
    test('a postal code is tidied up', () {
      expect(normalizeLocation('t5j0n3'), 'T5J 0N3');
      expect(normalizeLocation(' t5j  0n3 '), 'T5J 0N3');
      expect(normalizeLocation('T5J-0N3'), 'T5J 0N3');
    });

    test('an address is kept, with its spaces collapsed', () {
      expect(normalizeLocation('10123   99 Street NW'), '10123 99 Street NW');
    });

    test('anything too short to be either is refused', () {
      for (final bad in ['', '   ', 'T5', 'T5J', '123', 'ab']) {
        expect(normalizeLocation(bad), isNull, reason: '"$bad"');
      }
      expect(normalizeLocation('x' * 121), isNull);
    });

    Future<void> pumpStep(
      WidgetTester tester, {
      LocateDevice? locate,
      PostalCodeFor? postalCodeFor,
      void Function(String)? onChanged,
    }) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LocationStep(
            location: '',
            onLocationChanged: onChanged ?? (_) {},
            locate: locate ?? () async => (latitude: 53.5444, longitude: -113.4909),
            postalCodeFor: postalCodeFor ?? (_, _) async => 'T5J 0N3',
          ),
        ),
      ));
    }

    testWidgets('"Use my current location" fills in the postal code and never shows coordinates', (tester) async {
      var latest = '';
      await pumpStep(tester, onChanged: (v) => latest = v);
      expect(find.text('Latitude'), findsNothing);
      expect(find.text('Longitude'), findsNothing);

      await tester.tap(find.byKey(const Key('use-current-location')));
      await settle(tester);

      expect(tester.widget<TextField>(find.byKey(const Key('location-field'))).controller!.text, 'T5J 0N3');
      expect(latest, 'T5J 0N3');
      expect(find.textContaining('found your postal code'), findsOneWidget);
      expect(find.textContaining('53.5'), findsNothing);
      expect(find.textContaining('113.4'), findsNothing);
    });

    testWidgets('when the phone cannot say the postal code, the person is asked to type it', (tester) async {
      await pumpStep(tester, postalCodeFor: (_, _) async => null);
      await tester.tap(find.byKey(const Key('use-current-location')));
      await settle(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('location-field'))).controller!.text, isEmpty);
      expect(find.textContaining('type your postal code or address'), findsOneWidget);
      expect(find.textContaining('53.5'), findsNothing);
    });

    testWidgets('a refused or unavailable location explains it and offers typing instead', (tester) async {
      await pumpStep(tester, locate: () async => throw 'Location permission was denied.');
      await tester.tap(find.byKey(const Key('use-current-location')));
      await settle(tester);
      expect(find.textContaining('Location permission was denied.'), findsOneWidget);
      expect(find.textContaining('Type your postal code or address instead'), findsOneWidget);
    });

    testWidgets('while it looks, the button says so and waits', (tester) async {
      final pending = Completer<({double latitude, double longitude})>();
      await pumpStep(tester, locate: () => pending.future);
      await tester.tap(find.byKey(const Key('use-current-location')));
      await tester.pump();
      expect(find.text('Finding your location…'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('use-current-location'))).onPressed, isNull);
      pending.complete((latitude: 53.5, longitude: -113.5));
      await settle(tester);
      expect(find.text('Use my current location'), findsOneWidget);
    });

    testWidgets('typing something that is neither a postal code nor an address shows an error', (tester) async {
      var latest = '';
      await pumpStep(tester, onChanged: (v) => latest = v);
      await tester.enterText(find.byKey(const Key('location-field')), 'T5');
      await tester.pump();
      expect(find.text(kInvalidLocationMessage), findsOneWidget);
      expect(latest, 'T5');

      await tester.enterText(find.byKey(const Key('location-field')), 't5j0n3');
      await tester.pump();
      expect(find.text(kInvalidLocationMessage), findsNothing);
    });

    testWidgets('the request is sent with the location, and notifications are asked for only now', (tester) async {
      bigScreen(tester);
      final server = Server();
      final push = FakePush(granted: false);
      final service = PushService(backend: push);
      await service.start();
      PushService.instance = service;
      expect(push.prompts, 0, reason: 'nothing is asked before a request is sent');

      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: OnboardingScreen(initialCategory: findCategoryBySlug('plumbing'))));
        await tester.tap(find.text('Today'));
        await tester.pump();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('location-field')), 't5j0n3');
        await tester.pump();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(push.prompts, 0);

        await tester.enterText(find.byType(TextField).first, '7805550100');
        await tester.pump();
        expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '(780) 555-0100');
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
        await settle(tester);

        final post = server.to('/requests/', method: 'POST').single;
        final body = jsonDecode(post.body) as Map<String, dynamic>;
        expect(body['location'], 'T5J 0N3');
        expect(body['phone'], '+17805550100');
        expect(body.keys, isNot(contains('lat')));
        expect(body.toString(), isNot(contains('53.5444')));
        expect(push.prompts, 1, reason: 'the first request is sent, so notifications are asked for now');
        expect(find.byType(HomeScreen), findsOneWidget);
      }, () => server.client);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('History cards', () {
    Future<void> pumpCard(WidgetTester tester, ServiceRequestRecord request) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ServiceRequestCard(request: request, onMessage: (_) {}, onReview: (_) {}))),
      ));
    }

    test('a service the catalog does not list gets a readable name, never the raw slug', () {
      expect(categoryLabel('cleaning'), 'Cleaning');
      expect(categoryLabel('hot-tub-repair'), 'Hot Tub Repair');
      expect(categoryLabel('plumbing'), 'Plumbing');
      expect(categoryLabel(''), '');
    });

    testWidgets('a waitlisted request for an unlisted service reads "Cleaning" with an hourglass', (tester) async {
      await pumpCard(tester, requestRecord(category: 'cleaning', status: 'waitlisted', urgency: 'exploring'));
      expect(find.text('Cleaning'), findsOneWidget);
      expect(find.text('cleaning'), findsNothing);
      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
      expect(find.byIcon(Icons.assignment_outlined), findsNothing);
    });

    testWidgets('every card says where and how soon, so a new request is not blank', (tester) async {
      await pumpCard(tester, requestRecord());
      expect(find.byKey(const Key('request-where-7')), findsOneWidget);
      expect(find.text('Edmonton · Needed today'), findsOneWidget);
    });

    testWidgets('the phone number is shown the way people write it', (tester) async {
      await pumpCard(tester, requestRecord());
      expect(find.text('(780) 555-0100'), findsOneWidget);
      expect(find.text('+17805550100'), findsNothing);
    });

    testWidgets('on a completed job Message and Rate provider share one row, and Completed is said once', (tester) async {
      await pumpCard(tester, requestRecord(accepted: [offerJson(completed: true)]));
      expect(find.text('Completed'), findsOneWidget); // the pill
      final message = tester.getTopLeft(find.byKey(const Key('message-42')));
      final rate = tester.getTopLeft(find.byKey(const Key('rate-42')));
      expect((message.dy - rate.dy).abs(), lessThan(4), reason: 'one row, not two rows with a gap');
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('the first screen and the client menu', () {
    testWidgets('the role question sits in the middle of the screen, not pinned to the top', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(home: RoleChoiceScreen(onChosen: (_) {})));
      final welcome = tester.getTopLeft(find.text('Welcome to Tabmatch'));
      expect(welcome.dy, greaterThan(2400 * 0.25));
      final cards = tester.getBottomLeft(find.byKey(const Key('role-provider')));
      expect(cards.dy, lessThan(2400 * 0.8));
      expect(find.text('You can switch any time from the menu.'), findsOneWidget);
    });

    testWidgets('the role screen still fits a small phone', (tester) async {
      bigScreen(tester, size: const Size(720, 1100));
      await tester.pumpWidget(MaterialApp(home: RoleChoiceScreen(onChosen: (_) {})));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('role-client')), findsOneWidget);
      expect(find.byKey(const Key('role-provider')), findsOneWidget);
    });

    testWidgets('the client menu has no demo provider sign-up', (tester) async {
      bigScreen(tester);
      final key = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(MaterialApp(home: Scaffold(key: key, drawer: const AppDrawer(), body: const SizedBox())));
      key.currentState!.openDrawer();
      await settle(tester);
      expect(find.text('Provider Sign-Up (demo)'), findsNothing);
      expect(find.textContaining('demo'), findsNothing);
      for (final item in ['About Us', 'Mission & Vision', 'Favorites', 'Settings', 'Switch role']) {
        expect(find.text(item), findsOneWidget, reason: item);
      }
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('the Profile tab', () {
    Future<void> pumpSettings(WidgetTester tester, Server server) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsBody(api: null))));
      await settle(tester);
    }

    testWidgets('says who is signed in', (tester) async {
      final server = Server();
      await http.runWithClient(() async {
        await pumpSettings(tester, server);
        expect(find.byKey(const Key('account-card')), findsOneWidget);
        expect(find.text('Pat Client'), findsOneWidget);
        expect(find.text('pat@example.com'), findsOneWidget);
        expect(find.byKey(const Key('account-signed-out')), findsNothing);
      }, () => server.client);
    });

    testWidgets('shows the email alone when the account has no name', (tester) async {
      final server = Server()..me = {'email': 'pat@example.com', 'role': 'customer', 'full_name': ''};
      await http.runWithClient(() async {
        await pumpSettings(tester, server);
        expect(find.byKey(const Key('account-name')), findsNothing);
        expect(find.text('pat@example.com'), findsOneWidget);
      }, () => server.client);
    });

    testWidgets('says so when nobody is signed in', (tester) async {
      await AuthStorage.clear();
      final server = Server();
      await http.runWithClient(() async {
        await pumpSettings(tester, server);
        expect(find.byKey(const Key('account-signed-out')), findsOneWidget);
        expect(find.text('pat@example.com'), findsNothing);
        expect(server.to('/accounts/me/'), isEmpty);
      }, () => server.client);
    });

    testWidgets('the rest of the page still works if the account cannot be loaded', (tester) async {
      final server = Server()..me = null;
      await http.runWithClient(() async {
        await pumpSettings(tester, server);
        expect(find.text('Notifications'), findsOneWidget);
        expect(find.text('Log out'), findsOneWidget);
      }, () => server.client);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('the Notifications switch tells the truth', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsBody(api: null))));
      await settle(tester);
    }

    bool switchOn(WidgetTester tester) => tester.widget<Switch>(find.byType(Switch)).value;

    Future<void> usePush(FakePush push) async {
      final service = PushService(backend: push);
      await service.start();
      PushService.instance = service;
    }

    testWidgets('it is off when this build or phone cannot show notifications', (tester) async {
      final server = Server();
      await http.runWithClient(() async {
        await pumpSettings(tester);
        expect(switchOn(tester), isFalse);
      }, () => server.client);
    });

    testWidgets('it is off when the person said no to the phone prompt, and says why when turned on', (tester) async {
      final server = Server();
      final push = FakePush(granted: false, grantWhenAsked: false);
      await usePush(push);
      await http.runWithClient(() async {
        await pumpSettings(tester);
        expect(switchOn(tester), isFalse);
        await tester.tap(find.byType(Switch));
        await settle(tester);
        expect(push.prompts, 1);
        expect(switchOn(tester), isFalse);
        expect(find.textContaining('Notifications are off for Tabmatch on this phone'), findsOneWidget);
        expect(server.to('/devices/', method: 'POST'), isEmpty);
      }, () => server.client);
    });

    testWidgets('turning it on asks the phone and registers it when allowed', (tester) async {
      final server = Server();
      final push = FakePush(granted: false);
      await usePush(push);
      await http.runWithClient(() async {
        await pumpSettings(tester);
        await tester.tap(find.byType(Switch));
        await settle(tester);
        expect(push.prompts, 1);
        expect(switchOn(tester), isTrue);
        expect(server.to('/devices/', method: 'POST'), hasLength(1));
      }, () => server.client);
    });

    testWidgets('it is on when the phone allows notifications, and turning it off sticks', (tester) async {
      final server = Server();
      final push = FakePush(granted: true);
      await usePush(push);
      await http.runWithClient(() async {
        await pumpSettings(tester);
        expect(switchOn(tester), isTrue);
        await tester.tap(find.byType(Switch));
        await settle(tester);
        expect(switchOn(tester), isFalse);
        expect(server.to('/devices/', method: 'DELETE'), hasLength(1));

        await tester.pumpWidget(const SizedBox());
        await pumpSettings(tester);
        expect(switchOn(tester), isFalse, reason: 'the choice is remembered');
      }, () => server.client);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('notifications are asked for once, at the right moment', () {
    test('starting the app never shows the prompt, and a phone that already allows them registers quietly', () async {
      final server = Server();
      await http.runWithClient(() async {
        final denied = FakePush(granted: false);
        final a = PushService(backend: denied);
        await a.start();
        expect(denied.prompts, 0);
        expect(server.to('/devices/'), isEmpty);
        a.disposeForTest();

        final allowed = FakePush(granted: true);
        final b = PushService(backend: allowed);
        await b.start();
        expect(allowed.prompts, 0);
        expect(server.to('/devices/', method: 'POST'), hasLength(1));
        b.disposeForTest();
      }, () => server.client);
    });

    test('the first request asks once; a second request does not ask again', () async {
      final server = Server();
      await http.runWithClient(() async {
        final backend = FakePush(granted: false, grantWhenAsked: false);
        final push = PushService(backend: backend);
        await push.start();
        expect(await push.askAfterFirstRequest(), isFalse);
        expect(await push.askAfterFirstRequest(), isFalse);
        expect(backend.prompts, 1);
        push.disposeForTest();
      }, () => server.client);
    });

    test('when they say yes the phone is registered with the server', () async {
      final server = Server();
      await http.runWithClient(() async {
        final push = PushService(backend: FakePush(granted: false));
        await push.start();
        expect(await push.askAfterFirstRequest(), isTrue);
        expect(server.to('/devices/', method: 'POST'), hasLength(1));
        push.disposeForTest();
      }, () => server.client);
    });

    test('already allowed means no prompt at all', () async {
      final server = Server();
      await http.runWithClient(() async {
        final backend = FakePush(granted: true);
        final push = PushService(backend: backend);
        await push.start();
        expect(await push.askAfterFirstRequest(), isTrue);
        expect(backend.prompts, 0);
        push.disposeForTest();
      }, () => server.client);
    });

    test('a build without push never asks and never throws', () async {
      final backend = FakePush(configured: false);
      final push = PushService(backend: backend);
      await push.start();
      expect(await push.askAfterFirstRequest(), isFalse);
      expect(await push.notificationsOn(), isFalse);
      expect(await push.setNotifications(true), isFalse);
      expect(backend.prompts, 0);
    });
  });
}
