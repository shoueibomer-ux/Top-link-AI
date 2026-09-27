import 'package:flutter/foundation.dart';

/// Thrown when the build's API configuration is unsafe or missing. Carries a
/// message written for whoever is producing the build, not for end users.
class ApiConfigException implements Exception {
  ApiConfigException(this.message);

  final String message;

  @override
  String toString() => 'ApiConfigException: $message';
}

/// Build-time API configuration (security audit finding H4).
///
/// Before this existed the base URL was hard-coded to plain `http://` with no
/// way to override it, so shipping a release meant hand-editing source — and
/// one careless `http://api.example.com` would have sent every token and
/// contact detail in the clear. Nothing at the OS level would have stopped
/// it: this app talks through Dart's `http` package (raw sockets), which
/// ignores Android's `usesCleartextTraffic` and iOS's App Transport Security.
/// So it is enforced here, in code:
///
///  * `--dart-define=API_BASE_URL=https://api.example.com/api` sets the
///    backend. **Release builds require it, and require `https://`.**
///  * `--dart-define=API_KEY=<production key>` sets the shared API key.
///    **Release builds require it, and refuse the dev placeholder** — that
///    default would otherwise ship inside every install.
///  * Debug/profile builds keep working with no flags: `localhost` (or
///    `10.0.2.2` on the Android emulator) and the dev key; an `http://`
///    override is allowed there so a real phone can reach a LAN dev server.
///
/// The resolve* functions take every input as a parameter so they can be
/// tested without a release build.
class ApiConfig {
  static const _baseUrlDefine = String.fromEnvironment('API_BASE_URL');
  static const _apiKeyDefine = String.fromEnvironment('API_KEY');

  /// The placeholder the backend also falls back to when DEBUG=True (see
  /// config/settings.py). Public knowledge — must never reach a release.
  static const devApiKey = 'dev-local-shared-key';

  static String baseUrl() => resolveApiBaseUrl(
        override: _baseUrlDefine,
        isRelease: kReleaseMode,
        isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      );

  static String apiKey() => resolveApiKey(override: _apiKeyDefine, isRelease: kReleaseMode);

  /// Checks an explicitly supplied URL (e.g. `ApiClient(baseUrl: ...)`) with
  /// the same rules as the resolved default.
  static String checkBaseUrl(String url) => validateBaseUrl(url, isRelease: kReleaseMode);

  /// Called once at startup (see main.dart) so a misconfigured release build
  /// fails immediately and visibly, instead of every request quietly failing
  /// inside a screen's catch-all.
  static void validate() {
    baseUrl();
    apiKey();
  }
}

/// The API base URL for this build. See [ApiConfig].
String resolveApiBaseUrl({required String override, required bool isRelease, required bool isAndroid}) {
  final trimmed = override.trim();
  if (trimmed.isNotEmpty) return validateBaseUrl(trimmed, isRelease: isRelease);

  if (isRelease) {
    throw ApiConfigException(
      'API_BASE_URL is not set. Release builds must be built with '
      '--dart-define=API_BASE_URL=https://<your-backend>/api.',
    );
  }
  // The Android emulator can't reach the host machine via "localhost" — that
  // resolves to the emulator itself. 10.0.2.2 is its alias for the host.
  final host = isAndroid ? '10.0.2.2' : 'localhost';
  return 'http://$host:8000/api';
}

/// Returns [url] without a trailing slash, or throws if it is unusable for
/// this build type.
String validateBaseUrl(String url, {required bool isRelease}) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty || (uri.scheme != 'https' && uri.scheme != 'http')) {
    throw ApiConfigException('API base URL "$url" is not a valid http(s) URL.');
  }
  if (isRelease && uri.scheme != 'https') {
    throw ApiConfigException(
      'API base URL "$url" is not HTTPS. Release builds refuse to send '
      'tokens and contact details over cleartext HTTP.',
    );
  }
  return url.trim().replaceFirst(RegExp(r'/+$'), '');
}

/// The shared API key for this build. See [ApiConfig].
String resolveApiKey({required String override, required bool isRelease}) {
  final trimmed = override.trim();
  if (isRelease && (trimmed.isEmpty || trimmed == ApiConfig.devApiKey)) {
    throw ApiConfigException(
      'API_KEY is ${trimmed.isEmpty ? 'not set' : 'the public dev placeholder'}. '
      'Release builds must be built with --dart-define=API_KEY=<the production key>.',
    );
  }
  return trimmed.isEmpty ? ApiConfig.devApiKey : trimmed;
}
