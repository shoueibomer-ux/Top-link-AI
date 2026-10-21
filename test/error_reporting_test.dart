import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:toplinkai_app/monitoring/error_reporting.dart';

void main() {
  test('error reporting is off when the build has no SENTRY_DSN', () {
    expect(errorReportingEnabled, isFalse);
  });

  test('personal data in error messages is replaced', () {
    final text = scrubText(
      'send failed for jane.doe@example.com, phone +1 (780) 555-0100, '
      'token eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjo0Mn0.c2lnbmF0dXJl, Bearer abc.def, '
      'fcm dK3x9Qz7Lm2Np4Rs6Tv8Wy0Ab1Cd3Ef5',
    );
    for (final secret in ['jane.doe', '555-0100', 'eyJhbGci', 'abc.def', 'dK3x9Qz7']) {
      expect(text, isNot(contains(secret)));
    }
    expect(text, startsWith('send failed for'));
  });

  test('events lose the user, request, extras and breadcrumb data', () {
    final event = SentryEvent(
      user: SentryUser(id: '42', email: 'a@example.com'),
      request: SentryRequest(url: 'https://x/api/messages/?q=hi', data: {'body': 'private'}),
      // ignore: deprecated_member_use
      extra: {'body': 'private chat message'},
      message: SentryMessage('could not send to a@example.com'),
      exceptions: [SentryException(type: 'StateError', value: 'bad token eyJhbGciOiJIUzI1NiJ9.eyJ4IjoxfQ.c2ln')],
      breadcrumbs: [Breadcrumb(message: 'GET https://x/api/?email=a@example.com', data: {'url': 'https://x'})],
    );

    final scrubbed = scrubEvent(event);

    expect(scrubbed.user, isNull);
    expect(scrubbed.request, isNull);
    // ignore: deprecated_member_use
    expect(scrubbed.extra, isNull);
    expect(scrubbed.message!.formatted, isNot(contains('a@example.com')));
    expect(scrubbed.exceptions!.single.type, 'StateError');
    expect(scrubbed.exceptions!.single.value, isNot(contains('eyJ')));
    expect(scrubbed.breadcrumbs!.single.data, isNull);
    expect(scrubbed.breadcrumbs!.single.message, isNot(contains('a@example.com')));
  });
}
