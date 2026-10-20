import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/api_client.dart';
import 'package:toplinkai_app/api/provider_profile.dart';
import 'package:toplinkai_app/api/service_request.dart';
import 'package:toplinkai_app/home/home_screen.dart';
import 'package:toplinkai_app/messaging/conversation_screen.dart';
import 'package:toplinkai_app/messaging/push_service.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';
import 'package:toplinkai_app/provider/provider_leads_tab.dart';
import 'package:toplinkai_app/provider/provider_session.dart';

// Chat: the status on each History card, the Message buttons and unread badges, the conversation screen
// (text, photos, terms, report, block, call, polling) and push notifications.

const _upload = 'https://r2.example/upload?sig=abc';

ServiceRequestRecord record({
  List<Map<String, dynamic>> accepted = const [],
  String status = 'new',
}) => ServiceRequestRecord.fromJson({
  'id': 7,
  'category': 'plumbing',
  'city': 'Edmonton',
  'problem_description': '',
  'phone': '+17805550100',
  'status': status,
  'created_at': '2026-10-10T12:00:00Z',
  'accepted_offers': accepted,
});

Map<String, dynamic> offer(int id, String name, {bool completed = false}) => {
  'offer_id': id,
  'provider': {'id': id, 'business_name': name},
  'hired': completed,
  'job_completed': completed,
  'can_complete': !completed,
};

Map<String, dynamic> msg(
  int id,
  String body, {
  bool mine = false,
  bool removed = false,
  String? photo,
}) => {
  'id': id,
  'mine': mine,
  'created_at': '2026-10-10T12:0$id:00Z',
  'removed': removed,
  'body': removed ? '' : body,
  'photo_url': photo,
};

/// A fake chat server. It records every request and answers the way messaging.views does.
class Chat {
  Chat({
    this.termsAccepted = true,
    this.photos = true,
    this.canSend = true,
    this.blocked = false,
    this.dialNumber = '+17805550101',
  });

  bool termsAccepted;
  bool photos;
  bool canSend;
  bool blocked;
  String dialNumber;
  final messages = <Map<String, dynamic>>[];
  final requests = <http.Request>[];
  var _nextId = 100;
  int unread = 0;
  Map<String, dynamic>? uploadResponse;

  Iterable<http.Request> to(String part, {String? method}) => requests.where(
    (r) => r.url.path.contains(part) && (method == null || r.method == method),
  );

  Map<String, dynamic> get page => {
    'messages': messages,
    'other_name': 'Ace Plumbing',
    'blocked_by_me': blocked,
    'can_send': canSend && !blocked,
    'terms_accepted': termsAccepted,
    'photos_enabled': photos,
  };

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  http.Client get client => MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (request.method == 'PUT') {
      return http.Response('', 200); // the photo upload to storage
    }
    if (path.endsWith('/messaging/terms/')) {
      if (request.method == 'POST') termsAccepted = true;
      return json({
        'accepted': termsAccepted,
        'text': 'Be respectful and keep it about the job.',
      });
    }
    if (path.endsWith('/conversations/')) {
      return json({
        'conversations': [
          {
            'id': 9,
            'offer_id': 42,
            'request_id': 7,
            'other_name': 'Ace Plumbing',
            'unread_count': unread,
            'last_message': null,
            'blocked_by_me': false,
          },
        ],
        'total_unread': unread,
      });
    }
    if (path.endsWith('/conversations/open/')) {
      return json({
        'id': 9,
        'offer_id': 42,
        'request_id': 7,
        'other_name': 'Ace Plumbing',
        'unread_count': 0,
        'blocked_by_me': false,
        'terms_accepted': termsAccepted,
      });
    }
    final base = RegExp(r'/conversations/9/(\w+)/?(\d+)?/?(\w+)?/?$')
        .firstMatch(path);
    if (base != null) {
      switch (base.group(1)) {
        case 'messages':
          if (base.group(3) == 'report') return json({'reported': true}, 201);
          if (request.method == 'POST') {
            if (!termsAccepted) {
              return json({
                'detail': 'Agree to the chat rules first.',
                'code': 'terms_required',
              }, 403);
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final created = msg(
              _nextId++,
              body['body'] as String? ?? '',
              mine: true,
              photo: body['photo_key'] != null
                  ? 'https://r2.example/view'
                  : null,
            );
            messages.add(created);
            return json(created, 201);
          }
          final since = int.tryParse(
            request.url.queryParameters['since_id'] ?? '',
          );
          final listed = since == null
              ? messages
              : messages.where((m) => (m['id'] as int) > since).toList();
          return json({...page, 'messages': listed});
        case 'read':
          unread = 0;
          return json({'unread_count': 0});
        case 'photos':
          return json(
            uploadResponse ??
                {
                  'key': 'chat/9/new.jpg',
                  'upload_url': _upload,
                  'headers': {'Content-Type': 'image/jpeg'},
                  'max_bytes': 8388608,
                },
          );
        case 'block':
          blocked = request.method == 'POST';
          return json({'blocked_by_me': blocked});
        case 'call':
          return json({
            'mode': 'direct',
            'number': dialNumber,
            'name': 'Ace Plumbing',
          });
      }
    }
    if (path.endsWith('/devices/')) {
      return json({'registered': request.method == 'POST'});
    }
    return json({'detail': 'unexpected ${request.method} $path'}, 404);
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

Widget screen(
  Chat chat, {
  Future<PickedPhoto?> Function(ImageSource)? pick,
  Future<bool> Function(Uri)? dial,
  Duration poll = const Duration(seconds: 4),
}) => MaterialApp(
  home: ConversationScreen(
    session: AuthSession(),
    conversationId: 9,
    otherName: 'Ace Plumbing',
    pollInterval: poll,
    pickPhoto: pick ?? (_) async => null,
    openDialer: dial ?? (_) async => true,
  ),
);

Future<void> closeScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    const SizedBox(),
  ); // disposes the screen, which stops its polling timer
}

Future<void> typeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('message-input')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('send-button')));
  await settle(tester);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthStorage.save(access: 'tok-1', refresh: 'ref-1');
  });

  // -------------------------------------------------------------------------------------------------
  group('the status of a request', () {
    test('waiting for a provider until one accepts', () {
      expect(requestStatusOf(record()), RequestStatus.waiting);
      expect(requestStatusLabel(record()), 'Waiting for a provider');
    });

    test('accepted by the provider\'s name, one or several', () {
      expect(
        requestStatusLabel(record(accepted: [offer(1, 'Ace Plumbing')])),
        'Accepted by Ace Plumbing',
      );
      expect(
        requestStatusLabel(
          record(accepted: [offer(1, 'Ace'), offer(2, 'Best')]),
        ),
        'Accepted by Ace and Best',
      );
      expect(
        requestStatusLabel(
          record(
            accepted: [offer(1, 'Ace'), offer(2, 'Best'), offer(3, 'Cool')],
          ),
        ),
        'Accepted by Ace, Best and Cool',
      );
      expect(
        requestStatusOf(record(accepted: [offer(1, 'Ace')])),
        RequestStatus.accepted,
      );
    });

    test('completed once the job is marked done', () {
      final done = record(
        accepted: [offer(1, 'Ace', completed: true), offer(2, 'Best')],
      );
      expect(requestStatusOf(done), RequestStatus.completed);
      expect(requestStatusLabel(done), 'Completed');
    });

    test('a request for a service that has not opened is Waitlisted', () {
      expect(requestStatusLabel(record(status: 'waitlisted')), 'Waitlisted');
    });

    testWidgets('each History card shows its status', (tester) async {
      Future<void> shows(ServiceRequestRecord r, String text) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ServiceRequestCard(request: r)),
          ),
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('request-status')),
            matching: find.text(text),
          ),
          findsOneWidget,
        );
      }

      await shows(record(), 'Waiting for a provider');
      await shows(
        record(accepted: [offer(1, 'Ace Plumbing')]),
        'Accepted by Ace Plumbing',
      );
      await shows(
        record(accepted: [offer(1, 'Ace Plumbing', completed: true)]),
        'Completed',
      );
    });
  });

  group('the wording now fits in-app chat', () {
    test('nothing in the app promises a call or text any more', () {
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final text = file.readAsStringSync();
        expect(text, isNot(contains('phone or text')), reason: file.path);
        expect(text, isNot(contains('reach out by')), reason: file.path);
      }
      final home = File('lib/home/home_screen.dart').readAsStringSync();
      expect(home, contains('you can message them'));
    });

    testWidgets('History says a provider can be messaged once they accept', (
      tester,
    ) async {
      final chat = Chat();
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: HistoryTab())),
          );
          await settle(tester);
          expect(
            find.textContaining('you can message them right here'),
            findsOneWidget,
          );
          expect(find.textContaining('phone or text'), findsNothing);
        },
        () => MockClient(
          (r) async => http.Response(
            jsonEncode({
              'requests': [],
              'conversations': [],
              'total_unread': 0,
            }),
            200,
          ),
        ),
      );
      expect(chat.requests, isEmpty);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('Message buttons and unread counts', () {
    testWidgets(
      'an accepted provider on a History card has a Message button with the unread count',
      (tester) async {
        var tapped = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ServiceRequestCard(
                request: record(accepted: [offer(42, 'Ace Plumbing')]),
                onMessage: (_) => tapped++,
                unreadByOffer: const {42: 3},
              ),
            ),
          ),
        );
        expect(find.byKey(const Key('message-42')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('unread-42')),
            matching: find.text('3'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('message-42')));
        expect(tapped, 1);
      },
    );

    testWidgets(
      'no unread messages means no badge, and a request nobody accepted has no Message button',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ServiceRequestCard(
                request: record(accepted: [offer(42, 'Ace Plumbing')]),
                onMessage: (_) {},
                unreadByOffer: const {42: 0},
              ),
            ),
          ),
        );
        expect(find.byKey(const Key('unread-42')), findsNothing);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ServiceRequestCard(request: record(), onMessage: (_) {}),
            ),
          ),
        );
        expect(find.textContaining('Message'), findsNothing);
      },
    );

    testWidgets(
      'History loads the unread counts and opens the chat from the Message button',
      (tester) async {
        bigScreen(tester);
        final chat = Chat()..unread = 2;
        chat.messages.add(msg(1, 'Hello from Ace'));
        final requestsJson = {
          'requests': [
            {
              'id': 7,
              'category': 'plumbing',
              'city': 'Edmonton',
              'problem_description': '',
              'phone': '+17805550100',
              'status': 'new',
              'created_at': '2026-10-10T12:00:00Z',
              'accepted_offers': [offer(42, 'Ace Plumbing')],
            },
          ],
        };
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/requests/mine/')) {
            return http.Response(jsonEncode(requestsJson), 200);
          }
          return chat.client
              .send(
                http.Request(request.method, request.url)
                  ..body = request.body
                  ..headers.addAll(request.headers),
              )
              .then(http.Response.fromStream);
        });
        await http.runWithClient(() async {
          await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: HistoryTab())),
          );
          await settle(tester);
          expect(
            find.descendant(
              of: find.byKey(const Key('unread-42')),
              matching: find.text('2'),
            ),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const Key('message-42')));
          await settle(tester);
          expect(find.byType(ConversationScreen), findsOneWidget);
          expect(find.text('Hello from Ace'), findsOneWidget);
          expect(chat.to('/conversations/open/'), hasLength(1));
          expect(jsonDecode(chat.to('/conversations/open/').single.body), {
            'offer_id': 42,
          });
          await closeScreen(tester);
        }, () => client);
      },
    );

    testWidgets(
      'a provider sees Message only on accepted leads, with the unread count',
      (tester) async {
        ProviderLead lead(int id, LeadStatus status) => ProviderLead(
          offerId: id,
          requestId: 7,
          serviceSlug: 'plumbing',
          serviceName: 'Plumbing',
          city: 'Edmonton',
          status: status,
          clientName: status == LeadStatus.accepted ? 'Pat C.' : null,
        );
        var opened = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  LeadCard(
                    lead: lead(1, LeadStatus.accepted),
                    onMessage: (_) => opened++,
                    unread: 4,
                  ),
                  LeadCard(
                    lead: lead(2, LeadStatus.awaitingReply),
                    onMessage: (_) {},
                  ),
                  LeadCard(
                    lead: lead(3, LeadStatus.declined),
                    onMessage: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.byKey(const Key('message-lead-1')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('unread-lead-1')),
            matching: find.text('4'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('message-lead-2')), findsNothing);
        expect(find.byKey(const Key('message-lead-3')), findsNothing);
        await tester.tap(find.byKey(const Key('message-lead-1')));
        expect(opened, 1);
      },
    );
  });

  // -------------------------------------------------------------------------------------------------
  group('the chat screen', () {
    testWidgets('shows the conversation, mine on one side, and marks it read', (
      tester,
    ) async {
      bigScreen(tester);
      final chat = Chat()
        ..messages.addAll([
          msg(1, 'Hi, can you come at 3?', mine: true),
          msg(2, 'Yes, see you then'),
        ]);
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        expect(find.text('Hi, can you come at 3?'), findsOneWidget);
        expect(find.text('Yes, see you then'), findsOneWidget);
        expect(find.byKey(const Key('chat-title')), findsOneWidget);
        expect(find.text('Ace Plumbing'), findsOneWidget);
        final mineX = tester.getTopRight(find.byKey(const Key('message-1'))).dx;
        final theirsX = tester
            .getTopLeft(find.byKey(const Key('message-2')))
            .dx;
        expect(
          mineX,
          greaterThan(tester.getSize(find.byType(Scaffold)).width / 2),
        ); // on the right
        expect(
          theirsX,
          lessThan(tester.getSize(find.byType(Scaffold)).width / 2),
        ); // on the left
        final read = chat.to('/read/', method: 'POST').single;
        expect(jsonDecode(read.body), {'last_id': 2});
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets('every request carries the API key and the login', (
      tester,
    ) async {
      final chat = Chat();
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        await closeScreen(tester);
      }, () => chat.client);
      for (final r in chat.requests) {
        expect(r.headers['X-API-Key'], isNotEmpty, reason: r.url.path);
        expect(r.headers['Authorization'], 'Bearer tok-1', reason: r.url.path);
      }
    });

    testWidgets('an empty chat invites the first message', (tester) async {
      final chat = Chat();
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        expect(find.byKey(const Key('chat-empty')), findsOneWidget);
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets('sending adds the message and clears the box', (tester) async {
      final chat = Chat();
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        await typeAndSend(tester, '  Is 3pm ok?  ');
        expect(find.text('Is 3pm ok?'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('message-input')))
              .controller!
              .text,
          '',
        );
        expect(jsonDecode(chat.to('/messages/', method: 'POST').single.body), {
          'body': 'Is 3pm ok?',
        });
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets('the send button is off until there is something to send', (
      tester,
    ) async {
      final chat = Chat();
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('send-button')))
              .onPressed,
          isNull,
        );
        await tester.enterText(find.byKey(const Key('message-input')), '   ');
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('send-button')))
              .onPressed,
          isNull,
        );
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets(
      'the first message asks for the chat rules, and sends after they are agreed',
      (tester) async {
        final chat = Chat(termsAccepted: false);
        await http.runWithClient(() async {
          await tester.pumpWidget(screen(chat));
          await settle(tester);
          await typeAndSend(tester, 'Hello');
          expect(find.text('Chat rules'), findsOneWidget);
          expect(
            find.text('Be respectful and keep it about the job.'),
            findsOneWidget,
          );
          expect(
            chat.to('/messages/', method: 'POST'),
            isEmpty,
          ); // nothing sent before they agree

          await tester.tap(find.byKey(const Key('terms-agree')));
          await settle(tester);
          expect(chat.to('/messaging/terms/', method: 'POST'), hasLength(1));
          expect(find.text('Hello'), findsOneWidget);
          await closeScreen(tester);
        }, () => chat.client);
      },
    );

    testWidgets('declining the rules sends nothing and keeps what was typed', (
      tester,
    ) async {
      final chat = Chat(termsAccepted: false);
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        await typeAndSend(tester, 'Hello');
        await tester.tap(find.byKey(const Key('terms-decline')));
        await settle(tester);
        expect(chat.to('/messages/', method: 'POST'), isEmpty);
        expect(chat.to('/messaging/terms/', method: 'POST'), isEmpty);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('message-input')))
              .controller!
              .text,
          'Hello',
        );
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets(
      'new messages arrive by polling, asking only for what is newer',
      (tester) async {
        final chat = Chat()..messages.add(msg(1, 'first'));
        await http.runWithClient(() async {
          await tester.pumpWidget(
            screen(chat, poll: const Duration(milliseconds: 200)),
          );
          await settle(tester);
          expect(find.text('first'), findsOneWidget);

          chat.messages.add(msg(2, 'second, from the provider'));
          await tester.pump(const Duration(milliseconds: 250));
          await settle(tester);
          expect(find.text('second, from the provider'), findsOneWidget);
          final polls = chat
              .to('/messages/', method: 'GET')
              .where((r) => r.url.queryParameters.containsKey('since_id'))
              .toList();
          expect(polls, isNotEmpty);
          expect(polls.first.url.queryParameters['since_id'], '1');
          expect(find.text('first'), findsOneWidget); // not duplicated
          await closeScreen(tester);
        }, () => chat.client);
      },
    );

    testWidgets('polling stops when the screen is closed', (tester) async {
      final chat = Chat();
      await http.runWithClient(() async {
        await tester.pumpWidget(
          screen(chat, poll: const Duration(milliseconds: 200)),
        );
        await settle(tester);
        await closeScreen(tester);
        final before = chat.requests.length;
        await tester.pump(const Duration(seconds: 2));
        expect(chat.requests.length, before);
      }, () => chat.client);
    });

    testWidgets('a message a moderator removed shows as removed', (
      tester,
    ) async {
      final chat = Chat()..messages.add(msg(1, 'secret', removed: true));
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        expect(find.text('Message removed by a moderator'), findsOneWidget);
        expect(find.text('secret'), findsNothing);
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets('a failed load says so and can be retried', (tester) async {
      var calls = 0;
      final chat = Chat();
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/messages/') && calls++ == 0) {
          return http.Response('{"detail":"Conversation not found."}', 404);
        }
        return chat.client
            .send(
              http.Request(request.method, request.url)
                ..body = request.body
                ..headers.addAll(request.headers),
            )
            .then(http.Response.fromStream);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        expect(find.text('Conversation not found.'), findsOneWidget);
        await tester.tap(find.text('Try again'));
        await settle(tester);
        expect(find.byKey(const Key('message-input')), findsOneWidget);
        await closeScreen(tester);
      }, () => client);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('safety: report, block, call', () {
    testWidgets('long-pressing their message reports it with a reason', (
      tester,
    ) async {
      bigScreen(tester);
      final chat = Chat()..messages.add(msg(5, 'Pay me outside the app'));
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        await tester.longPress(find.byKey(const Key('message-5')));
        await tester.pumpAndSettle();
        expect(find.text('Report this message'), findsOneWidget);
        await tester.tap(find.byKey(const Key('report-scam')));
        await settle(tester);
        final report = chat.to('/report/').single;
        expect(
          report.url.path,
          endsWith('/conversations/9/messages/5/report/'),
        );
        expect(jsonDecode(report.body), {'reason': 'scam'});
        expect(
          find.text('Thanks. We will review this message.'),
          findsOneWidget,
        );
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets('your own messages and removed ones cannot be reported', (
      tester,
    ) async {
      bigScreen(tester);
      final chat = Chat()
        ..messages.addAll([
          msg(1, 'mine', mine: true),
          msg(2, 'gone', removed: true),
        ]);
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        await tester.longPress(find.byKey(const Key('message-1')));
        await tester.pump();
        await tester.longPress(find.byKey(const Key('message-2')));
        await tester.pump();
        expect(find.text('Report this message'), findsNothing);
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets('backing out of the report sends nothing', (tester) async {
      bigScreen(tester);
      final chat = Chat()..messages.add(msg(5, 'hi'));
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        await tester.longPress(find.byKey(const Key('message-5')));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5)); // outside the dialog
        await tester.pumpAndSettle();
        expect(chat.to('/report/'), isEmpty);
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets(
      'blocking asks first, then replaces the composer with an unblock banner',
      (tester) async {
        bigScreen(tester);
        final chat = Chat();
        await http.runWithClient(() async {
          await tester.pumpWidget(screen(chat));
          await settle(tester);
          await tester.tap(find.byKey(const Key('chat-menu')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Block this person'));
          await tester.pumpAndSettle();
          expect(chat.to('/block/'), isEmpty); // not until they confirm
          await tester.tap(find.byKey(const Key('confirm-block')));
          await settle(tester);
          expect(chat.to('/block/', method: 'POST'), hasLength(1));
          expect(find.byKey(const Key('blocked-banner')), findsOneWidget);
          expect(find.byKey(const Key('message-input')), findsNothing);

          await tester.tap(find.text('Unblock'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('confirm-block')));
          await settle(tester);
          expect(chat.to('/block/', method: 'DELETE'), hasLength(1));
          expect(find.byKey(const Key('message-input')), findsOneWidget);
          await closeScreen(tester);
        }, () => chat.client);
      },
    );

    testWidgets(
      'when the other person blocked you, you only see that you cannot send',
      (tester) async {
        final chat = Chat(canSend: false);
        await http.runWithClient(() async {
          await tester.pumpWidget(screen(chat));
          await settle(tester);
          expect(find.byKey(const Key('cannot-send-banner')), findsOneWidget);
          expect(
            find.text("You can't send messages in this conversation."),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('blocked-banner')),
            findsNothing,
          ); // it never says who blocked whom
          expect(find.byKey(const Key('message-input')), findsNothing);
          await closeScreen(tester);
        }, () => chat.client);
      },
    );

    testWidgets(
      'Call asks the server for the number and opens the phone dialer',
      (tester) async {
        Uri? dialed;
        final chat = Chat(dialNumber: '+17805550101');
        await http.runWithClient(() async {
          await tester.pumpWidget(
            screen(
              chat,
              dial: (uri) async {
                dialed = uri;
                return true;
              },
            ),
          );
          await settle(tester);
          await tester.tap(find.byKey(const Key('call-button')));
          await settle(tester);
          expect(dialed.toString(), 'tel:+17805550101');
          expect(chat.to('/call/'), hasLength(1));
          await closeScreen(tester);
        }, () => chat.client);
      },
    );

    testWidgets('if the dialer cannot open, it says so', (tester) async {
      final chat = Chat();
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat, dial: (_) async => false));
        await settle(tester);
        await tester.tap(find.byKey(const Key('call-button')));
        await settle(tester);
        expect(find.text('Could not open the phone dialer.'), findsOneWidget);
        await closeScreen(tester);
      }, () => chat.client);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('photos', () {
    final photo = PickedPhoto(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      contentType: 'image/jpeg',
    );

    testWidgets('picking a photo uploads it to storage and then sends it', (
      tester,
    ) async {
      bigScreen(tester);
      final chat = Chat();
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat, pick: (_) async => photo));
        await settle(tester);
        await tester.tap(find.byKey(const Key('attach-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('attach-gallery')));
        await settle(tester);

        final presign = chat.to('/photos/').single;
        expect(jsonDecode(presign.body), {'content_type': 'image/jpeg'});
        final put = chat.requests.firstWhere((r) => r.method == 'PUT');
        expect(put.url.toString(), _upload);
        expect(put.bodyBytes, [1, 2, 3, 4]);
        expect(put.headers['Content-Type'], contains('image/jpeg'));
        final sent = jsonDecode(
          chat.to('/messages/', method: 'POST').single.body,
        ) as Map<String, dynamic>;
        expect(sent['photo_key'], 'chat/9/new.jpg');
        expect(find.byKey(const Key('photo-100')), findsOneWidget);
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets(
      'the upload to storage carries neither our API key nor the login token',
      (tester) async {
        bigScreen(tester);
        final chat = Chat();
        await http.runWithClient(() async {
          await tester.pumpWidget(screen(chat, pick: (_) async => photo));
          await settle(tester);
          await tester.tap(find.byKey(const Key('attach-button')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('attach-camera')));
          await settle(tester);
          final put = chat.requests.firstWhere((r) => r.method == 'PUT');
          expect(
            put.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('x-api-key')),
          );
          expect(
            put.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('authorization')),
          );
          await closeScreen(tester);
        }, () => chat.client);
      },
    );

    testWidgets('cancelling the picker does nothing', (tester) async {
      bigScreen(tester);
      final chat = Chat();
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        await tester.tap(find.byKey(const Key('attach-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('attach-gallery')));
        await settle(tester);
        expect(chat.to('/photos/'), isEmpty);
        expect(chat.to('/messages/', method: 'POST'), isEmpty);
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets('without photo storage the photo button is hidden', (
      tester,
    ) async {
      final chat = Chat(photos: false);
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat));
        await settle(tester);
        expect(find.byKey(const Key('attach-button')), findsNothing);
        expect(find.byKey(const Key('message-input')), findsOneWidget);
        await closeScreen(tester);
      }, () => chat.client);
    });

    testWidgets('a failed upload tells the person and sends no message', (
      tester,
    ) async {
      bigScreen(tester);
      final chat = Chat();
      final client = MockClient((request) async {
        if (request.method == 'PUT') return http.Response('denied', 403);
        return chat.client
            .send(
              http.Request(request.method, request.url)
                ..body = request.body
                ..headers.addAll(request.headers),
            )
            .then(http.Response.fromStream);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(screen(chat, pick: (_) async => photo));
        await settle(tester);
        await tester.tap(find.byKey(const Key('attach-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('attach-gallery')));
        await settle(tester);
        expect(find.textContaining('could not be uploaded'), findsOneWidget);
        expect(chat.to('/messages/', method: 'POST'), isEmpty);
        await closeScreen(tester);
      }, () => client);
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('the chat API calls', () {
    test('sending, reading and fetching newer messages use the cursor and the login', () async {
      final chat = Chat()..messages.add(msg(1, 'a'));
      await http.runWithClient(() async {
        final api = ApiClient();
        final page = await api.getMessages('tok', 9, sinceId: 1);
        expect(page.messages, isEmpty);
        expect(chat.requests.last.url.queryParameters, {'since_id': '1'});
        final latest = await api.getMessages('tok', 9);
        expect(latest.messages.single.body, 'a');
        expect(chat.requests.last.url.queryParameters, isEmpty);
        expect(chat.requests.last.headers['Authorization'], 'Bearer tok');
      }, () => chat.client);
    });

    test(
      'a 403 with the terms_required code becomes ChatTermsRequired',
      () async {
        final chat = Chat(termsAccepted: false);
        await http.runWithClient(() async {
          await expectLater(
            ApiClient().sendMessage('tok', 9, body: 'hi'),
            throwsA(isA<ChatTermsRequired>()),
          );
        }, () => chat.client);
      },
    );

    test(
      'a 401 means sign in again; other errors carry the server message',
      () async {
        await http.runWithClient(
          () async {
            await expectLater(
              ApiClient().getConversations('tok'),
              throwsA(isA<SessionExpiredException>()),
            );
          },
          () => MockClient(
            (_) async =>
                http.Response('{"detail":"Given token not valid"}', 401),
          ),
        );
        await http.runWithClient(
          () async {
            await expectLater(
              ApiClient().getConversations('tok'),
              throwsA(
                isA<ApiException>().having(
                  (e) => e.message,
                  'message',
                  'Nope.',
                ),
              ),
            );
          },
          () =>
              MockClient((_) async => http.Response('{"detail":"Nope."}', 400)),
        );
      },
    );

    test('conversations list parses unread counts keyed by offer', () async {
      final chat = Chat()..unread = 5;
      await http.runWithClient(() async {
        final result = await ApiClient().getConversations('tok');
        expect(result.totalUnread, 5);
        expect(result.conversations.single.offerId, 42);
        expect(result.conversations.single.unreadCount, 5);
      }, () => chat.client);
    });

    test('a device is registered and removed with the login', () async {
      final chat = Chat();
      await http.runWithClient(() async {
        await ApiClient().registerDevice('tok', 'phone-token');
        await ApiClient().unregisterDevice('tok', 'phone-token');
      }, () => chat.client);
      expect(jsonDecode(chat.to('/devices/', method: 'POST').single.body), {
        'token': 'phone-token',
        'platform': 'android',
      });
      expect(jsonDecode(chat.to('/devices/', method: 'DELETE').single.body), {
        'token': 'phone-token',
      });
    });
  });

  // -------------------------------------------------------------------------------------------------
  group('push notifications', () {
    test('only chat notifications name a conversation', () {
      expect(
        conversationIdFromPush({'type': 'chat', 'conversation_id': '9'}),
        9,
      );
      expect(
        conversationIdFromPush({'type': 'chat', 'conversation_id': 12}),
        12,
      );
      expect(
        conversationIdFromPush({'type': 'other', 'conversation_id': '9'}),
        isNull,
      );
      expect(conversationIdFromPush({'type': 'chat'}), isNull);
      expect(
        conversationIdFromPush({'type': 'chat', 'conversation_id': 'abc'}),
        isNull,
      );
      expect(conversationIdFromPush({}), isNull);
    });

    test(
      'a build without Firebase config leaves push off and never throws',
      () async {
        final backend = FakePush(configured: false);
        final push = PushService(backend: backend);
        await push.start();
        expect(push.enabled, isFalse);
        await push.register();
        await push.unregister();
        expect(backend.tokenCalls, 0);
      },
    );

    test(
      'with Firebase, a signed-in phone registers its token with the server',
      () async {
        final backend = FakePush(token: 'phone-token');
        final chat = Chat();
        await http.runWithClient(() async {
          final push = PushService(backend: backend);
          await push.start();
          expect(push.enabled, isTrue);
          expect(backend.askedPermission, isFalse, reason: 'starting the app never shows the permission prompt');
          expect(
            jsonDecode(
              chat.to('/devices/', method: 'POST').single.body,
            )['token'],
            'phone-token',
          );
          push.disposeForTest();
        }, () => chat.client);
      },
    );

    test('nothing is registered while nobody is signed in', () async {
      await AuthStorage.clear();
      final chat = Chat();
      await http.runWithClient(() async {
        final push = PushService(backend: FakePush());
        await push.start();
        expect(chat.to('/devices/'), isEmpty);
        push.disposeForTest();
      }, () => chat.client);
    });

    test('signing out removes the phone from the server while the login still exists', () async {
      final chat = Chat();
      await http.runWithClient(() async {
        final push = PushService(backend: FakePush(token: 'phone-token'));
        await push.start();
        await push.unregister();
        expect(jsonDecode(chat.to('/devices/', method: 'DELETE').single.body), {
          'token': 'phone-token',
        });
        push.disposeForTest();
      }, () => chat.client);
    });

    test('a refreshed token is registered again', () async {
      final backend = FakePush(token: 'phone-token');
      final chat = Chat();
      await http.runWithClient(() async {
        final push = PushService(backend: backend);
        await push.start();
        backend.tokenValue = 'new-token';
        backend.refresh.add('new-token');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final tokens = chat
            .to('/devices/', method: 'POST')
            .map((r) => jsonDecode(r.body)['token'])
            .toList();
        expect(tokens, ['phone-token', 'new-token']);
        push.disposeForTest();
      }, () => chat.client);
    });

    test(
      'a chat notification while the app is open asks the lists to refresh',
      () async {
        final backend = FakePush();
        final chat = Chat();
        await http.runWithClient(() async {
          final push = PushService(backend: backend);
          await push.start();
          final before = push.chatActivity.value;
          backend.foreground.add({'type': 'chat', 'conversation_id': '9'});
          backend.foreground.add({'type': 'something-else'});
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(
            push.chatActivity.value,
            before + 1,
          ); // only the chat one counts
          push.disposeForTest();
        }, () => chat.client);
      },
    );

    testWidgets('tapping a chat notification opens that conversation', (
      tester,
    ) async {
      bigScreen(tester);
      final backend = FakePush();
      final chat = Chat()..messages.add(msg(1, 'See you at 3'));
      await http.runWithClient(() async {
        final push = PushService(
          backend: backend,
          sessionFactory: AuthSession.new,
        );
        await push.start();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: PushService.navigatorKey,
            home: const Scaffold(body: Text('home')),
          ),
        );
        backend.opened.add({'type': 'chat', 'conversation_id': '9'});
        await settle(tester);
        expect(find.byType(ConversationScreen), findsOneWidget);
        expect(find.text('See you at 3'), findsOneWidget);
        await closeScreen(tester);
        push.disposeForTest();
      }, () => chat.client);
    });
  });
}

class FakePush implements PushBackend {
  FakePush({this.configured = true, String? token = 'tok-device', this.granted = true, this.grantWhenAsked = true})
    : tokenValue = token;

  final bool configured;

  /// Whether the phone already allows notifications (an older Android, or the person said yes before).
  bool granted;

  /// What the person answers when the system prompt is shown.
  final bool grantWhenAsked;
  String? tokenValue;
  int tokenCalls = 0;
  int permissionPrompts = 0;
  bool get askedPermission => permissionPrompts > 0;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<Map<String, dynamic>>.broadcast();
  final opened = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Future<bool> init() async => configured;

  @override
  Future<void> requestPermission() async {
    permissionPrompts++;
    if (grantWhenAsked) granted = true;
  }

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<String?> token() async {
    tokenCalls++;
    return tokenValue;
  }

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage => foreground.stream;

  @override
  Stream<Map<String, dynamic>> get onOpenedFromNotification => opened.stream;

  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;

  @override
  Future<void> deleteToken() async {}
}
