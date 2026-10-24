import 'package:flutter_test/flutter_test.dart';
import 'package:toplinkai_app/api/api_client.dart';
import 'package:toplinkai_app/api/api_config.dart';
import 'package:toplinkai_app/main.dart';

// Security audit finding H4: the app had a hard-coded plain-http base URL and
// no way to override it, and nothing at the OS level stops Dart's `http`
// package from sending cleartext — so release builds must refuse an unsafe
// configuration themselves.

Matcher throwsConfigError(Pattern messageContains) => throwsA(
      isA<ApiConfigException>().having((e) => e.message, 'message', contains(messageContains)),
    );

void main() {
  group('base URL', () {
    test('debug builds default to localhost, or 10.0.2.2 on the Android emulator', () {
      expect(resolveApiBaseUrl(override: '', isRelease: false, isAndroid: false), 'http://localhost:8000/api');
      expect(resolveApiBaseUrl(override: '', isRelease: false, isAndroid: true), 'http://10.0.2.2:8000/api');
    });

    test('an override wins and has trailing slashes trimmed', () {
      expect(
        resolveApiBaseUrl(override: 'https://api.example.com/api//', isRelease: true, isAndroid: true),
        'https://api.example.com/api',
      );
      expect(
        resolveApiBaseUrl(override: '  https://api.example.com/api  ', isRelease: false, isAndroid: false),
        'https://api.example.com/api',
      );
    });

    test('a release build with no API_BASE_URL talks to https://tabmatch.ca/api, never localhost', () {
      expect(resolveApiBaseUrl(override: '', isRelease: true, isAndroid: true), 'https://tabmatch.ca/api');
      expect(resolveApiBaseUrl(override: '   ', isRelease: true, isAndroid: false), 'https://tabmatch.ca/api');
      expect(ApiConfig.productionApiBaseUrl, 'https://tabmatch.ca/api');
    });

    test('website pages of a default release build are on https://tabmatch.ca', () {
      final base = resolveApiBaseUrl(override: '', isRelease: true, isAndroid: true);
      expect(siteUrlFor(base, '/privacy/'), 'https://tabmatch.ca/privacy/');
      expect(siteUrlFor(base, '/delete-account/'), 'https://tabmatch.ca/delete-account/');
    });

    test('an older build pointed at the onrender.com host still works when given it explicitly', () {
      expect(
        resolveApiBaseUrl(override: 'https://toplinkai-backend.onrender.com/api', isRelease: true, isAndroid: true),
        'https://toplinkai-backend.onrender.com/api',
      );
    });

    test('a release build refuses a cleartext http:// URL', () {
      expect(
        () => resolveApiBaseUrl(override: 'http://api.example.com/api', isRelease: true, isAndroid: true),
        throwsConfigError('not HTTPS'),
      );
      expect(() => validateBaseUrl('http://10.0.2.2:8000/api', isRelease: true), throwsConfigError('not HTTPS'));
    });

    test('a debug build may use http:// (e.g. a LAN dev server for a real phone)', () {
      expect(
        resolveApiBaseUrl(override: 'http://192.168.1.20:8000/api', isRelease: false, isAndroid: true),
        'http://192.168.1.20:8000/api',
      );
    });

    test('malformed or non-http(s) URLs are refused in every build type', () {
      for (final bad in ['not a url', 'https://', 'ftp://example.com/api', '//example.com/api', 'example.com/api']) {
        expect(() => validateBaseUrl(bad, isRelease: false), throwsConfigError('not a valid'), reason: bad);
        expect(() => validateBaseUrl(bad, isRelease: true), throwsA(isA<ApiConfigException>()), reason: bad);
      }
    });
  });

  group('API key', () {
    test('debug builds fall back to the dev key', () {
      expect(resolveApiKey(override: '', isRelease: false), ApiConfig.devApiKey);
    });

    test('a supplied key is used as-is in any build type', () {
      expect(resolveApiKey(override: 'prod-key-123', isRelease: true), 'prod-key-123');
      expect(resolveApiKey(override: 'other-dev-key', isRelease: false), 'other-dev-key');
    });

    test('a release build with no API_KEY is refused', () {
      expect(() => resolveApiKey(override: '', isRelease: true), throwsConfigError('API_KEY is not set'));
    });

    test('a release build refuses the public dev placeholder even when passed explicitly', () {
      expect(
        () => resolveApiKey(override: ApiConfig.devApiKey, isRelease: true),
        throwsConfigError('dev placeholder'),
      );
    });
  });

  group('ApiClient', () {
    test('constructs with the debug defaults under test', () {
      // flutter test is a debug-mode run, so no --dart-define is needed.
      expect(ApiClient().baseUrl, anyOf('http://localhost:8000/api', 'http://10.0.2.2:8000/api'));
    });

    test('an explicit baseUrl is validated and normalised too', () {
      expect(ApiClient(baseUrl: 'https://api.example.com/api/').baseUrl, 'https://api.example.com/api');
      expect(() => ApiClient(baseUrl: 'not a url'), throwsA(isA<ApiConfigException>()));
    });
  });

  group('startup error screen', () {
    testWidgets('names the problem and how to fix it instead of showing the app', (tester) async {
      const message = 'API_KEY is not set. Release builds must be built with --dart-define=API_KEY=<the production key>.';
      await tester.pumpWidget(const ConfigErrorApp(message: message));

      expect(find.text('This build is misconfigured'), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(find.text('Unlock Tabmatch'), findsNothing); // no paywall behind it
    });
  });
}
