import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Crash and error reporting (Sentry), on only when the build was given
/// `--dart-define=SENTRY_DSN=...`. Without it the app runs exactly as before
/// and nothing is sent anywhere.
///
/// Errors only (no performance tracing, screenshots, view hierarchy or
/// session replay), and nothing personal: no user identity, no request data,
/// no print/log or tap breadcrumbs (those can carry message text), and any
/// email, phone number or token inside an error message is replaced before
/// sending. Same rules as the backend's config/sentry.py.
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');
const _sentryEnvironment = String.fromEnvironment('SENTRY_ENVIRONMENT');

bool get errorReportingEnabled => _sentryDsn.trim().isNotEmpty;

/// Starts the app through Sentry (so uncaught Flutter and Dart errors are
/// reported) when a DSN is configured, or just runs it when not.
Future<void> runWithErrorReporting(FutureOr<void> Function() appRunner) async {
  if (!errorReportingEnabled) {
    await appRunner();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn.trim();
      options.environment = _sentryEnvironment.isNotEmpty
          ? _sentryEnvironment
          : (kReleaseMode ? 'production' : 'development');
      options.sendDefaultPii = false;
      // Screenshots and view hierarchy are off by default; left that way.
      options.attachScreenshot = false;
      options.enablePrintBreadcrumbs = false;
      options.enableUserInteractionBreadcrumbs = false;
      options.enableAutoNativeBreadcrumbs = false;
      options.enableAutoPerformanceTracing = false;
      options.enableUserInteractionTracing = false;
      options.beforeSend = (event, hint) => scrubEvent(event);
      options.beforeBreadcrumb = (crumb, hint) => crumb == null ? null : scrubBreadcrumb(crumb);
    },
    appRunner: appRunner,
  );
}

const redacted = '[redacted]';

final _patterns = <RegExp>[
  // JWTs (the app's access/refresh tokens).
  RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
  RegExp(r'\bbearer\s+\S+', caseSensitive: false),
  RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
  // Long letter-and-digit runs: the API key, Google ID tokens, FCM tokens.
  RegExp(r'(?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{24,}'),
  // Phone numbers in any common format.
  RegExp(r'\+?\d[\d\s().-]{6,}\d'),
];

String scrubText(String value) {
  var out = value;
  for (final pattern in _patterns) {
    out = out.replaceAll(pattern, redacted);
  }
  return out;
}

@visibleForTesting
SentryEvent scrubEvent(SentryEvent event) {
  event.user = null;
  event.request = null;
  // ignore: deprecated_member_use
  event.extra = null;
  final message = event.message;
  if (message != null) event.message = SentryMessage(scrubText(message.formatted));
  for (final exception in event.exceptions ?? const <SentryException>[]) {
    final value = exception.value;
    if (value != null) exception.value = scrubText(value);
  }
  event.breadcrumbs = event.breadcrumbs?.map(scrubBreadcrumb).toList();
  return event;
}

/// Keeps what kind of step it was; drops its data (URLs, arguments).
@visibleForTesting
Breadcrumb scrubBreadcrumb(Breadcrumb crumb) {
  final message = crumb.message;
  crumb.message = message == null ? null : scrubText(message);
  crumb.data = null;
  return crumb;
}
