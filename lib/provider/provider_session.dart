import '../api/api_client.dart';
import 'auth_storage.dart';

/// Calls the backend as the signed-in provider. If the access token has
/// expired it renews it once from the refresh token and retries; if that fails
/// too, the stored tokens are cleared and [SessionExpiredException] is thrown
/// so the caller can send them back to sign-in.
class ProviderSession {
  ProviderSession({ApiClient? api}) : api = api ?? ApiClient();

  final ApiClient api;

  Future<T> authorized<T>(Future<T> Function(String accessToken) call) async {
    final access = await AuthStorage.getAccessToken();
    if (access == null) throw SessionExpiredException();
    try {
      return await call(access);
    } on SessionExpiredException {
      final refresh = await AuthStorage.getRefreshToken();
      if (refresh == null) {
        await AuthStorage.clear();
        rethrow;
      }
      try {
        final tokens = await api.refreshTokens(refresh);
        await AuthStorage.save(access: tokens.access, refresh: tokens.refresh);
        return await call(tokens.access);
      } on SessionExpiredException {
        await AuthStorage.clear();
        rethrow;
      }
    }
  }
}
