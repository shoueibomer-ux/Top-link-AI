import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:toplinkai_app/api/api_client.dart';
import 'package:toplinkai_app/api/api_config.dart';
import 'package:toplinkai_app/api/provider_profile.dart';
import 'package:toplinkai_app/onboarding/urgency_step.dart';

// The backend gates every endpoint on the shared X-API-Key header. These tests
// pin that the request calls send it — including the POST that submits a
// service request — so one call can't quietly drift onto its own headers.

Future<List<http.Request>> record(
  Future<void> Function(ApiClient client) body, {
  Object? responseBody,
  int postStatus = 201,
}) async {
  final seen = <http.Request>[];
  await http.runWithClient(
    () => body(ApiClient()),
    () => MockClient((request) async {
      seen.add(request);
      return http.Response(jsonEncode(responseBody ?? {}), request.method == 'POST' ? postStatus : 200);
    }),
  );
  return seen;
}

void expectApiKey(http.Request request) {
  final key = ApiConfig.apiKey();
  expect(key, isNotEmpty);
  expect(request.headers['X-API-Key'], key, reason: '${request.method} ${request.url.path}');
  expect(request.headers['Content-Type'], contains('application/json'));
}

void main() {
  test('submitting a service request POSTs to /requests/ with the API key', () async {
    final seen = await record(
      (client) async {
        final submission = await client.createServiceRequest(
          accessToken: 'tok-1',
          deviceId: 'dev-1',
          category: 'plumbing',
          phone: '+1 780 555 0100',
          consent: true,
          urgency: Urgency.today.apiValue,
        );
        expect(submission.requestId, 7);
      },
      responseBody: {'request_id': 7, 'status': 'new'},
    );

    expect(seen, hasLength(1));
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, endsWith('/api/requests/'));
    expectApiKey(seen.single);
    final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
    expect(body, containsPair('consent', true));
    expect(body, containsPair('category', 'plumbing'));
    expect(body, containsPair('urgency', 'today'));
    // Sent as the signed-in client.
    expect(seen.single.headers['Authorization'], 'Bearer tok-1');
  });

  test('the history and chat calls send the same key header', () async {
    final seen = await record((client) async {
      await client.getMyServiceRequests('tok-1');
      await client.refineChatMessage(message: 'leaking pipe', deviceId: 'dev-1');
    }, responseBody: {'requests': []}, postStatus: 200);

    expect(seen.map((r) => r.url.path), [endsWith('/api/requests/mine/'), endsWith('/api/chat/refine/')]);
    seen.forEach(expectApiKey);
  });

  test('your requests are fetched as the signed-in client, never by device id', () async {
    final seen = await record((client) async {
      await client.getMyServiceRequests('tok-1');
    }, responseBody: {'requests': []});

    expect(seen.single.headers['Authorization'], 'Bearer tok-1');
    expect(seen.single.url.queryParameters, isEmpty); // no device_id in the URL any more
  });

  test('marking a job complete POSTs the offer to the request', () async {
    final seen = await record(
      (client) async {
        final updated = await client.completeServiceRequest('tok-1', 7, 42);
        expect(updated.id, 7);
        expect(updated.acceptedOffers.single.jobCompleted, isTrue);
        expect(updated.acceptedOffers.single.canComplete, isFalse);
      },
      responseBody: {
        'id': 7,
        'category': 'plumbing',
        'accepted_offers': [
          {
            'offer_id': 42,
            'provider': {'id': 3, 'business_name': 'Ace Plumbing'},
            'hired': true,
            'job_completed': true,
            'can_complete': false,
          },
        ],
      },
      postStatus: 200,
    );

    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, endsWith('/api/requests/7/complete/'));
    expect(seen.single.headers['Authorization'], 'Bearer tok-1');
    expect(jsonDecode(seen.single.body), {'offer_id': 42});
    expectApiKey(seen.single);
  });

  test('a client signs in by trading a Google token at /accounts/google/', () async {
    final seen = await record(
      (client) async {
        final result = await client.signInClientWithGoogle('google-token');
        expect(result.tokens.access, 'a');
        expect(result.email, 'pat@example.com');
        expect(result.isNewAccount, isTrue);
      },
      responseBody: {'access': 'a', 'refresh': 'r', 'email': 'pat@example.com', 'full_name': 'Pat', 'is_new_account': true},
      postStatus: 200,
    );

    expect(seen.single.url.path, endsWith('/api/accounts/google/'));
    expect(jsonDecode(seen.single.body), {'id_token': 'google-token'});
    expect(seen.single.headers.containsKey('Authorization'), isFalse);
    expectApiKey(seen.single);
  });

  test('the provider lead list is read as the signed-in provider', () async {
    final seen = await record((client) async {
      final leads = await client.getProviderLeads('tok-p');
      expect(leads.single.serviceName, 'Plumbing');
      expect(leads.single.status, LeadStatus.accepted);
      expect(leads.single.clientName, 'Pat C.');
    }, responseBody: {
      'leads': [
        {
          'offer_id': 5,
          'request_id': 7,
          'service': {'slug': 'plumbing', 'name': 'Plumbing'},
          'city': 'Edmonton',
          'urgency': 'today',
          'status': 'accepted',
          'description': 'Leaking sink',
          'client_name': 'Pat C.',
        },
      ],
    });

    expect(seen.single.url.path, endsWith('/api/provider/leads/'));
    expect(seen.single.headers['Authorization'], 'Bearer tok-p');
    expectApiKey(seen.single);
  });

  test('a 401 on your requests means sign in again; a 403 is an error message', () async {
    Future<void> check(int status, Object matcher, String body) => http.runWithClient(
          () => expectLater(ApiClient().getMyServiceRequests('tok'), throwsA(matcher)),
          () => MockClient((_) async => http.Response(body, status)),
        );
    await check(401, isA<SessionExpiredException>(), jsonEncode({'detail': 'Given token not valid'}));
    await check(
      403,
      isA<ApiException>().having((e) => e.message, 'message', 'Only client accounts can do this.'),
      jsonEncode({'detail': 'Only client accounts can do this.'}),
    );
    await check(
      401,
      isA<ApiException>().having((e) => e.message, 'message', 'Missing or invalid API key.'),
      jsonEncode({'detail': 'Missing or invalid API key.'}),
    );
  });

  test('catalog calls send the key too, with and without the provider flag', () async {
    final seen = await record((client) async {
      await client.getCatalog();
      await client.getCatalog(includeUnlaunched: true);
    }, responseBody: <dynamic>[]);

    expect(seen, hasLength(2));
    seen.forEach(expectApiKey);
    expect(seen[0].url.queryParameters, isEmpty);
    expect(seen[1].url.queryParameters, {'include_unlaunched': 'true'});
  });

  test('a 401 from a rejected key surfaces the server message, not a login prompt', () async {
    await http.runWithClient(
      () async {
        await expectLater(
          ApiClient().createServiceRequest(accessToken: 't', category: 'plumbing', phone: '1', consent: true),
          throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Missing or invalid API key.')),
        );
      },
      () => MockClient((_) async => http.Response(jsonEncode({'detail': 'Missing or invalid API key.'}), 401)),
    );
  });

  group('startup diagnostics', () {
    test('the summary line never contains the key', () {
      const key = 'abcDEF1234567890abcDEF1234567890abcDEF12345';
      final line = describeApiConfig(baseUrl: 'https://api.example.com/api', apiKey: key);
      expect(line, contains('https://api.example.com/api'));
      expect(line, contains('43 characters'));
      expect(line, isNot(contains(key)));
      expect(line, isNot(contains('abcDEF')));
    });

    test('the dev placeholder is named, not echoed as a length', () {
      final line = describeApiConfig(baseUrl: 'http://10.0.2.2:8000/api', apiKey: ApiConfig.devApiKey);
      expect(line, contains('dev placeholder'));
    });

    test('a real key with no API_BASE_URL warns that the build is aimed at the local server', () {
      final warning = apiConfigWarning(baseUrlOverride: '', apiKey: 'a-real-looking-production-key-0123456789');
      expect(warning, isNotNull);
      expect(warning, contains('API_BASE_URL'));
      expect(warning, isNot(contains('a-real-looking')));
    });

    test('no warning when the URL is set, or when only the dev key is in use', () {
      expect(apiConfigWarning(baseUrlOverride: 'https://x.example/api', apiKey: 'a-real-key-0123456789'), isNull);
      expect(apiConfigWarning(baseUrlOverride: '', apiKey: ApiConfig.devApiKey), isNull);
    });
  });
}
