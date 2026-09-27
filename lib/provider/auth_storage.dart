import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accessKey = 'provider_auth_access_token';
const _refreshKey = 'provider_auth_refresh_token';

/// Persists the JWT pair issued by accounts.views (RegisterView/LoginView) in
/// the platform's secure store — Android Keystore-wrapped AES-GCM, the iOS/
/// macOS Keychain — never in plain SharedPreferences.
///
/// Why this matters (security audit finding H3): SharedPreferences is an
/// unencrypted XML file on Android, readable on a rooted device or from a
/// backup, and the refresh token is good for 14 days — a copied file was a
/// two-week account takeover. The access/refresh keys are the same names as
/// before, so [_migrateLegacyTokens] can move a token an earlier build left
/// in SharedPreferences into the secure store (and delete the plaintext copy)
/// the first time it's read — nobody already logged in gets logged out, and
/// no plaintext copy lingers.
///
/// On iOS/macOS the Keychain items use `first_unlock_this_device`: they are
/// excluded from backups and never migrate to another device. (Android
/// backups are switched off in the manifest for the same reason.)
///
/// On web there is no secure store — the plugin falls back to WebCrypto-
/// encrypted localStorage, which is obfuscation, not protection from script
/// running on the same origin.
///
/// Provider-only for now: nothing in the customer-facing flow (Ask AI /
/// History) requires being logged in, so this is never read from there.
class AuthStorage {
  static const _secure = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static Future<void> save({required String access, required String refresh}) async {
    await _secure.write(key: _accessKey, value: access);
    await _secure.write(key: _refreshKey, value: refresh);
    // A fresh login supersedes any plaintext copy a previous build left.
    await _removeLegacyTokens();
  }

  static Future<String?> getAccessToken() => _read(_accessKey);

  static Future<String?> getRefreshToken() => _read(_refreshKey);

  static Future<bool> isLoggedIn() async {
    return await getAccessToken() != null;
  }

  static Future<void> clear() async {
    await _secure.delete(key: _accessKey);
    await _secure.delete(key: _refreshKey);
    await _removeLegacyTokens();
  }

  static Future<String?> _read(String key) async {
    await _migrateLegacyTokens();
    try {
      return await _secure.read(key: key);
    } catch (e) {
      // An unreadable secure store (a corrupted Keystore entry, say) must
      // read as "logged out", not crash whichever screen asked — the user
      // just logs in again. Never log the exception's detail: it can echo
      // stored values.
      debugPrint('AuthStorage: secure store unreadable, treating as logged out (${e.runtimeType})');
      return null;
    }
  }

  /// Moves tokens an earlier build stored in SharedPreferences into the
  /// secure store, then deletes the plaintext copies. A token already in the
  /// secure store wins — the legacy one is just deleted.
  static Future<void> _migrateLegacyTokens() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [_accessKey, _refreshKey]) {
      final legacy = prefs.getString(key);
      if (legacy == null) continue;
      try {
        if (await _secure.read(key: key) == null) {
          await _secure.write(key: key, value: legacy);
        }
      } catch (_) {
        // Couldn't reach the secure store: leave the legacy copy for the next
        // attempt rather than losing the session.
        continue;
      }
      await prefs.remove(key);
    }
  }

  static Future<void> _removeLegacyTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }
}
