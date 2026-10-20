import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/provider_profile.dart';
import 'package:toplinkai_app/messaging/conversation_screen.dart';
import 'package:toplinkai_app/messaging/push_service.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';
import 'package:toplinkai_app/provider/provider_leads_tab.dart';
import 'package:toplinkai_app/provider/provider_session.dart';

// Accept / Decline on the provider's lead cards (the same answer as replying YES / NO to the text), and the
// request summary under the name in a chat.

Map<String, dynamic> leadJson({int id = 42, String status = 'awaiting_reply', Map<String, dynamic> extra = const {}}) => {
      'offer_id': id,
      'request_id': 7,
      'service': {'slug': 'plumbing', 'name': 'Plumbing'},
      'city': 'Edmonton',
      'urgency': 'today',
      'status': status,
      'sent_at': '2026-10-20T12:00:00Z',
      'responded_at': null,
      'hired': false,
      'job_completed': false,
      ...extra,
    };

class LeadServer {
  LeadServer({List<Map<String, dynamic>>? leads}) : leads = leads ?? [leadJson()];

  List<Map<String, dynamic>> leads;
  final requests = <http.Request>[];

  /// What accept / decline answer: 200 normally, 409 for "already answered", 401 for an expired session.
  int answerStatus = 200;
  String answerDetail = 'You have already answered this request.';
  bool offline = false;

  /// While set, an answer waits for it (to look at the card while it is being sent).
  Completer<void>? hold;

  Iterable<http.Request> to(String part, {String? method}) =>
      requests.where((r) => r.url.path.contains(part) && (method == null || r.method == method));

  http.Client get client => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);
        if (path.endsWith('/accounts/token/refresh/')) return json({'detail': 'expired'}, 401);
        if (path.endsWith('/provider/leads/') && request.method == 'GET') return json({'leads': leads});
        final answer = RegExp(r'/provider/leads/(\d+)/(accept|decline)/$').firstMatch(path);
        if (answer != null && request.method == 'POST') {
          if (offline) throw http.ClientException('no network');
          if (hold != null) await hold!.future;
          if (answerStatus == 409) return json({'detail': answerDetail}, 409);
          if (answerStatus == 401) return json({'detail': 'expired'}, 401);
          final id = int.parse(answer.group(1)!);
          final accepted = answer.group(2) == 'accept';
          final updated = leadJson(
            id: id,
            status: accepted ? 'accepted' : 'declined',
            extra: accepted
                ? {'client_name': 'Pat C.', 'description': 'Leaking kitchen sink', 'location': 'T5J 0N3'}
                : const {},
          );
          leads = [for (final l in leads) l['offer_id'] == id ? updated : l];
          return json({'lead': updated});
        }
        if (path.endsWith('/conversations/')) return json({'conversations': [], 'total_unread': 0});
        if (path.endsWith('/devices/')) return json({'registered': true});
        return json({'detail': 'nothing here'}, 404);
      });
}

class FakePush implements PushBackend {
  FakePush({this.granted = false});

  bool granted;
  int prompts = 0;

  @override
  Future<bool> init() async => true;

  @override
  Future<void> requestPermission() async {
    prompts++;
    granted = true;
  }

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<String?> token() async => 'phone-token';

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get onOpenedFromNotification => const Stream.empty();

  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;

  @override
  Future<void> deleteToken() async {}
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

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthStorage.save(access: 'tok-1', refresh: 'ref-1');
  });

  tearDown(() {
    PushService.instance.disposeForTest();
    PushService.instance = PushService();
  });

  Future<void> pumpLeads(WidgetTester tester, LeadServer server, {VoidCallback? onExpired}) async {
    bigScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProviderLeadsTab(session: AuthSession(), onSessionExpired: onExpired ?? () {})),
    ));
    await settle(tester);
  }

  // -------------------------------------------------------------------------------------------------
  group('the lead card', () {
    testWidgets('a request waiting for an answer has Accept and Decline, and says how it can also be answered', (tester) async {
      final server = LeadServer();
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        expect(find.byKey(const Key('accept-lead-42')), findsOneWidget);
        expect(find.byKey(const Key('decline-lead-42')), findsOneWidget);
        expect(find.text('Or reply YES 42 or NO 42 to the text we sent.'), findsOneWidget);
        expect(find.textContaining('Accept or decline here'), findsOneWidget);
      }, () => server.client);
    });

    testWidgets('every card shows when it arrived and its number, so two requests are never alike', (tester) async {
      final server = LeadServer(leads: [leadJson(id: 42), leadJson(id: 43, status: 'declined')]);
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        final first = tester.widget<Text>(find.byKey(const Key('lead-received-42'))).data!;
        final second = tester.widget<Text>(find.byKey(const Key('lead-received-43'))).data!;
        expect(first, startsWith('Received Oct 20, '));
        expect(first, endsWith('Request #42'));
        expect(second, endsWith('Request #43'));
        expect(first, isNot(second));
        expect(first, matches(RegExp(r'^Received Oct 2[01], \d{1,2}:\d{2} (AM|PM) · Request #42$')));
      }, () => server.client);
    });

    testWidgets('a request that has been answered has no buttons', (tester) async {
      final server = LeadServer(leads: [
        leadJson(id: 1, status: 'accepted', extra: {'client_name': 'Pat C.', 'description': 'Leaky tap'}),
        leadJson(id: 2, status: 'declined'),
        leadJson(id: 3, status: 'expired'),
      ]);
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        expect(find.textContaining('accept-lead'), findsNothing);
        expect(find.byKey(const Key('accept-lead-1')), findsNothing);
        expect(find.byKey(const Key('accept-lead-2')), findsNothing);
        expect(find.byKey(const Key('accept-lead-3')), findsNothing);
        expect(find.byKey(const Key('decline-lead-3')), findsNothing);
        expect(find.textContaining('Or reply YES'), findsNothing);
      }, () => server.client);
    });

    testWidgets('an accepted request shows the client, the description and where the job is', (tester) async {
      final server = LeadServer(leads: [
        leadJson(status: 'accepted', extra: {'client_name': 'Pat C.', 'description': 'Leaky tap', 'location': 'T5J 0N3'}),
      ]);
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        expect(find.text('Pat C.'), findsOneWidget);
        expect(find.text('Leaky tap'), findsOneWidget);
        expect(find.byKey(const Key('lead-location-42')), findsOneWidget);
        expect(find.text('T5J 0N3'), findsOneWidget);
      }, () => server.client);
    });

    testWidgets('before accepting the location is not shown', (tester) async {
      final server = LeadServer();
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        expect(find.byKey(const Key('lead-location-42')), findsNothing);
      }, () => server.client);
    });

    testWidgets('a card built without handlers (as before) shows no buttons', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LeadCard(lead: ProviderLead.fromJson(leadJson()))),
      ));
      expect(find.byKey(const Key('accept-lead-42')), findsNothing);
      expect(find.text('Request #42'), findsNothing); // the line also carries when it came
      expect(find.textContaining('Request #42'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('answering from the card', () {
    testWidgets('Accept sends the answer, shows the client details and offers Message', (tester) async {
      final server = LeadServer();
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        await tester.tap(find.byKey(const Key('accept-lead-42')));
        await settle(tester);

        final post = server.to('/provider/leads/42/accept/', method: 'POST').single;
        expect(post.headers['Authorization'], 'Bearer tok-1');
        expect(find.text('Accepted'), findsOneWidget);
        expect(find.text('Pat C.'), findsWidgets);
        expect(find.text('Leaking kitchen sink'), findsOneWidget);
        expect(find.text('T5J 0N3'), findsOneWidget);
        expect(find.byKey(const Key('accept-lead-42')), findsNothing);
        expect(find.byKey(const Key('decline-lead-42')), findsNothing);
        expect(find.byKey(const Key('message-lead-42')), findsOneWidget);
        expect(find.text('Accepted. You can message Pat C. now.'), findsOneWidget);
      }, () => server.client);
    });

    testWidgets('Decline asks first, and "Keep it" changes nothing', (tester) async {
      final server = LeadServer();
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        await tester.tap(find.byKey(const Key('decline-lead-42')));
        await settle(tester);
        expect(find.text('Decline this request?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('decline-keep')));
        await settle(tester);
        expect(server.to('/decline/'), isEmpty);
        expect(find.byKey(const Key('accept-lead-42')), findsOneWidget);
      }, () => server.client);
    });

    testWidgets('confirming Decline sends it and the card shows Declined', (tester) async {
      final server = LeadServer();
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        await tester.tap(find.byKey(const Key('decline-lead-42')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('decline-confirm')));
        await settle(tester);

        expect(server.to('/provider/leads/42/decline/', method: 'POST'), hasLength(1));
        expect(server.to('/accept/'), isEmpty);
        expect(find.text('Declined'), findsWidgets);
        expect(find.byKey(const Key('accept-lead-42')), findsNothing);
        expect(find.byKey(const Key('message-lead-42')), findsNothing);
        expect(find.text('Declined.'), findsOneWidget);
      }, () => server.client);
    });

    testWidgets('both buttons wait while the answer is being sent', (tester) async {
      final server = LeadServer()..hold = Completer<void>();
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        await tester.tap(find.byKey(const Key('accept-lead-42')));
        await tester.pump();
        expect(tester.widget<FilledButton>(find.byKey(const Key('accept-lead-42'))).onPressed, isNull);
        expect(tester.widget<OutlinedButton>(find.byKey(const Key('decline-lead-42'))).onPressed, isNull);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // a second tap while waiting sends nothing more
        await tester.tap(find.byKey(const Key('accept-lead-42')), warnIfMissed: false);
        await tester.pump();
        expect(server.to('/accept/'), hasLength(1));

        server.hold!.complete();
        await settle(tester);
        expect(find.text('Accepted'), findsOneWidget);
      }, () => server.client);
    });

    testWidgets('if it was already answered by text, the app says so and shows how it stands', (tester) async {
      final server = LeadServer()
        ..answerStatus = 409
        ..answerDetail = 'You have already answered this request.';
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        // meanwhile the provider answered NO by text
        server.leads = [leadJson(status: 'declined')];
        await tester.tap(find.byKey(const Key('accept-lead-42')));
        await settle(tester);
        expect(find.text('You have already answered this request.'), findsOneWidget);
        expect(find.byKey(const Key('accept-lead-42')), findsNothing, reason: 'the list reloaded');
        expect(find.text('Declined'), findsWidgets);
        expect(server.to('/provider/leads/', method: 'GET').length, 2);
      }, () => server.client);
    });

    testWidgets('with no connection it says so and the buttons come back', (tester) async {
      final server = LeadServer()..offline = true;
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        await tester.tap(find.byKey(const Key('accept-lead-42')));
        await settle(tester);
        expect(find.textContaining('Could not reach the server'), findsOneWidget);
        expect(tester.widget<FilledButton>(find.byKey(const Key('accept-lead-42'))).onPressed, isNotNull);
        expect(tester.widget<OutlinedButton>(find.byKey(const Key('decline-lead-42'))).onPressed, isNotNull);
      }, () => server.client);
    });

    testWidgets('an expired login sends the provider back to sign in', (tester) async {
      final server = LeadServer()..answerStatus = 401;
      var expired = 0;
      await http.runWithClient(() async {
        await pumpLeads(tester, server, onExpired: () => expired++);
        await tester.tap(find.byKey(const Key('accept-lead-42')));
        await settle(tester);
        expect(expired, greaterThan(0));
      }, () => server.client);
    });

    testWidgets('notifications are asked for after the first accept, and not after a decline', (tester) async {
      final server = LeadServer(leads: [leadJson(id: 42), leadJson(id: 43)]);
      final backend = FakePush();
      final push = PushService(backend: backend);
      await push.start();
      PushService.instance = push;
      await http.runWithClient(() async {
        await pumpLeads(tester, server);
        expect(backend.prompts, 0);

        await tester.tap(find.byKey(const Key('decline-lead-43')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('decline-confirm')));
        await settle(tester);
        expect(backend.prompts, 0, reason: 'declining is not what makes notifications matter');

        await tester.tap(find.byKey(const Key('accept-lead-42')));
        await settle(tester);
        expect(backend.prompts, 1);
        expect(server.to('/devices/', method: 'POST'), hasLength(1));
      }, () => server.client);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('the chat says what it is about', () {
    Future<void> pumpChat(WidgetTester tester, {required Map<String, dynamic> page, String summary = '', Size? size}) async {
      bigScreen(tester, size: size ?? const Size(1080, 2400));
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/conversations/9/messages/')) return http.Response(jsonEncode(page), 200);
        return http.Response(jsonEncode({'unread_count': 0}), 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: ConversationScreen(
            session: AuthSession(),
            conversationId: 9,
            otherName: 'Ace Plumbing',
            requestSummary: summary,
            pollInterval: const Duration(hours: 1),
          ),
        ));
        await settle(tester);
      }, () => client);
    }

    Map<String, dynamic> pageJson({String? summary}) => {
          'messages': [],
          'other_name': 'Ace Plumbing',
          'request_summary': ?summary,
          'can_send': true,
          'terms_accepted': true,
          'photos_enabled': false,
        };

    testWidgets('the header shows the service and the job under the name', (tester) async {
      await pumpChat(tester, page: pageJson(summary: 'Plumbing · Leaking kitchen sink'));
      expect(find.byKey(const Key('chat-title')), findsOneWidget);
      expect(find.text('Ace Plumbing'), findsOneWidget);
      expect(find.byKey(const Key('chat-subtitle')), findsOneWidget);
      expect(find.text('Plumbing · Leaking kitchen sink'), findsOneWidget);
      // the subtitle is below the name
      expect(tester.getTopLeft(find.byKey(const Key('chat-subtitle'))).dy, greaterThan(tester.getTopLeft(find.byKey(const Key('chat-title'))).dy));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it uses the summary it was opened with when the page does not carry one', (tester) async {
      await pumpChat(tester, page: pageJson(), summary: 'Electrical · Flickering lights');
      expect(find.text('Electrical · Flickering lights'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with no summary at all there is just the name', (tester) async {
      await pumpChat(tester, page: pageJson());
      expect(find.byKey(const Key('chat-subtitle')), findsNothing);
      expect(find.byKey(const Key('chat-title')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a long summary stays on one line and does not overflow a narrow phone', (tester) async {
      await pumpChat(
        tester,
        page: pageJson(summary: 'Plumbing · Water everywhere in the basement and rising by the minute, please call'),
        size: const Size(540, 1200),
      );
      expect(tester.takeException(), isNull);
      final subtitle = tester.widget<Text>(find.byKey(const Key('chat-subtitle')));
      expect(subtitle.maxLines, 1);
      expect(subtitle.overflow, TextOverflow.ellipsis);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
