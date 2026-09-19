import 'package:shared_preferences/shared_preferences.dart';

const _accessKey = 'provider_auth_access_token';
const _refreshKey = 'provider_auth_refresh_token';

/// Persists the JWT pair issued by accounts.views (RegisterView/LoginView) —
/// same SharedPreferences-backed pattern as device_id.dart/provider_id.dart,
/// just storing a token pair instead of a single UUID. Provider-only for
/// now: nothing in the customer-facing flow (Ask AI/History) requires being
/// logged in, so this is never read from there.
class AuthStorage {
  static Future<void> save({required String access, required String refresh}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    await prefs.setString(_refreshKey, refresh);
  }

  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessKey);
  }

  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshKey);
  }

  static Future<bool> isLoggedIn() async {
    return await getAccessToken() != null;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }
}
