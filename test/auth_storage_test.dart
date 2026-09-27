import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/provider/auth_storage.dart';

// Security audit finding H3: provider JWTs must live in the platform secure
// store, never in plain SharedPreferences (an unencrypted XML file on
// Android). The SharedPreferences key names below are the ones an earlier
// build used ("flutter."-prefixed on disk, bare here as the plugin's API
// sees them).
const _access = 'provider_auth_access_token';
const _refresh = 'provider_auth_refresh_token';

Future<Map<String, Object?>> _prefsSnapshot() async {
  final prefs = await SharedPreferences.getInstance();
  return {for (final key in prefs.getKeys()) key: prefs.get(key)};
}

void main() {
  const secure = FlutterSecureStorage();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('a fresh install is logged out', () async {
    expect(await AuthStorage.isLoggedIn(), isFalse);
    expect(await AuthStorage.getAccessToken(), isNull);
    expect(await AuthStorage.getRefreshToken(), isNull);
  });

  test('saved tokens round-trip through the secure store', () async {
    await AuthStorage.save(access: 'access-1', refresh: 'refresh-1');

    expect(await AuthStorage.getAccessToken(), 'access-1');
    expect(await AuthStorage.getRefreshToken(), 'refresh-1');
    expect(await AuthStorage.isLoggedIn(), isTrue);
    expect(await secure.read(key: _access), 'access-1');
    expect(await secure.read(key: _refresh), 'refresh-1');
  });

  test('tokens are never written to SharedPreferences', () async {
    await AuthStorage.save(access: 'access-1', refresh: 'refresh-1');

    final prefs = await _prefsSnapshot();
    expect(prefs.containsKey(_access), isFalse);
    expect(prefs.containsKey(_refresh), isFalse);
    expect(prefs.values.whereType<String>().any((v) => v.contains('-1')), isFalse);
  });

  test('clear() removes both tokens', () async {
    await AuthStorage.save(access: 'access-1', refresh: 'refresh-1');
    await AuthStorage.clear();

    expect(await AuthStorage.isLoggedIn(), isFalse);
    expect(await secure.read(key: _access), isNull);
    expect(await secure.read(key: _refresh), isNull);
  });

  group('migrating tokens an earlier build left in plain SharedPreferences', () {
    test('moves them to the secure store on first read and deletes the plaintext copy', () async {
      SharedPreferences.setMockInitialValues({_access: 'legacy-access', _refresh: 'legacy-refresh'});

      // Already-logged-in users stay logged in...
      expect(await AuthStorage.getAccessToken(), 'legacy-access');
      expect(await AuthStorage.getRefreshToken(), 'legacy-refresh');
      expect(await secure.read(key: _access), 'legacy-access');
      expect(await secure.read(key: _refresh), 'legacy-refresh');

      // ...and no plaintext copy remains.
      final prefs = await _prefsSnapshot();
      expect(prefs.containsKey(_access), isFalse);
      expect(prefs.containsKey(_refresh), isFalse);
    });

    test('a token already in the secure store wins; the legacy copy is just deleted', () async {
      FlutterSecureStorage.setMockInitialValues({_access: 'secure-access'});
      SharedPreferences.setMockInitialValues({_access: 'stale-legacy-access'});

      expect(await AuthStorage.getAccessToken(), 'secure-access');
      expect((await _prefsSnapshot()).containsKey(_access), isFalse);
    });

    test('a fresh login deletes a stale plaintext copy', () async {
      SharedPreferences.setMockInitialValues({_access: 'stale', _refresh: 'stale'});
      await AuthStorage.save(access: 'new-access', refresh: 'new-refresh');

      expect(await AuthStorage.getAccessToken(), 'new-access');
      expect(await _prefsSnapshot(), isEmpty);
    });

    test('log out also erases a plaintext copy that was never migrated', () async {
      SharedPreferences.setMockInitialValues({_access: 'legacy-access', _refresh: 'legacy-refresh'});
      await AuthStorage.clear();

      expect(await _prefsSnapshot(), isEmpty);
      expect(await AuthStorage.isLoggedIn(), isFalse);
    });

    test('unrelated SharedPreferences values are left alone', () async {
      SharedPreferences.setMockInitialValues({'device_id': 'dev-123', _access: 'legacy-access'});
      await AuthStorage.getAccessToken();

      expect((await _prefsSnapshot())['device_id'], 'dev-123');
    });
  });
}
