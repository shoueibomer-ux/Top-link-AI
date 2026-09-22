import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../onboarding/service_category.dart';
import 'app_notification.dart';
import 'auth_models.dart';
import 'chat_refine_result.dart';
import 'provider_match.dart';
import 'provider_onboarding.dart';
import 'real_provider.dart';
import 'subscription_status.dart';

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown by [ApiClient.unlockProvider] when the backend responds 402 —
/// this device isn't subscribed and didn't set `paid: true`. The UI uses
/// this to offer "pay $4.99 or subscribe" rather than a generic error.
class PaymentRequiredException extends ApiException {
  PaymentRequiredException(super.message, {required this.priceUsd});

  final String priceUsd;
}

// The Android emulator can't reach the host machine via "localhost" — that
// resolves to the emulator itself. 10.0.2.2 is its alias for the host.
String _defaultBaseUrl() {
  final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
  return 'http://$host:8000/api';
}

// Shared secret required by the backend (see matching.permissions.HasApiKey).
// Must match the backend's API_KEY. The default here is a dev-only value —
// a real deployment overrides it at build time with
// --dart-define=API_KEY=<the production key>, so the real secret never sits
// in source control.
const _apiKey = String.fromEnvironment('API_KEY', defaultValue: 'dev-local-shared-key');

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl();

  final String baseUrl;

  // Demo location (Edmonton) used to prefill the location step. provider_search
  // only covers a fixed set of Alberta cities (see provider_search.services.CITIES),
  // so demoCity pins searches to the one matching the demo coordinates rather
  // than deriving a city from lat/lng.
  static const demoLat = 53.5444;
  static const demoLng = -113.4909;
  static const demoCity = 'Edmonton';

  static const _headers = {
    'Content-Type': 'application/json',
    'X-API-Key': _apiKey,
  };

  // Adds the Bearer token on top of the usual headers — every accounts.*
  // endpoint that reads/writes a specific account needs both: the shared
  // API key (the app-wide anti-scraping gate, same as every other endpoint)
  // and the token (who, specifically, is asking).
  Map<String, String> _authHeaders(String accessToken) => {
        ..._headers,
        'Authorization': 'Bearer $accessToken',
      };

  /// Real providers for a category/city via Google Places (see
  /// provider_search.views.ProviderSearchView). Every result is masked
  /// (RealProvider.isUnlocked is false, phone is a masked string, address/
  /// website/mapsUrl are null) unless this device already unlocked that
  /// specific provider — see [unlockProvider]. `result.isSubscribed` is
  /// only a hint for that unlock prompt's copy, not a gate on this call.
  Future<ProviderSearchResult> searchRealProviders({
    required String category,
    required String city,
    required String deviceId,
  }) async {
    final uri = Uri.parse('$baseUrl/providers/search/').replace(queryParameters: {
      'category': category,
      'city': city,
      'device_id': deviceId,
    });
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw ApiException('Could not search providers (${response.statusCode}).');
    }
    return ProviderSearchResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See provider_search.views.ProviderUnlockView — the only way a real
  /// phone/address/website is ever revealed, and the only way a "Your
  /// requests" entry is created. Free (no `paid` flag needed) if this
  /// device has an active subscription; otherwise pass `paid: true` only
  /// after the client has actually gone through the $4.99 purchase flow
  /// (see ProviderUnlockDialog) — calling this with `paid: true` unprompted
  /// would just be lying to the backend about having paid, so callers must
  /// not do that.
  ///
  /// Throws [PaymentRequiredException] (never a raw 402 status check by
  /// callers) when neither condition holds, so the UI can offer "pay $4.99
  /// or subscribe" instead of a generic error.
  Future<RealProvider> unlockProvider({
    required String deviceId,
    required String placeId,
    required String category,
    required String city,
    bool paid = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/providers/unlock/'),
      headers: _headers,
      body: jsonEncode({
        'device_id': deviceId,
        'place_id': placeId,
        'category': category,
        'city': city,
        if (paid) 'paid': true,
      }),
    );
    if (response.statusCode == 402) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      throw PaymentRequiredException(
        decoded['detail'] as String? ?? 'Subscribe or pay to unlock this provider.',
        priceUsd: decoded['price_usd'] as String? ?? '4.99',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not unlock this provider.');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return RealProvider.fromJson(decoded['provider'] as Map<String, dynamic>);
  }

  Future<SubscriptionStatus> getSubscriptionStatus(String deviceId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/subscription/?device_id=$deviceId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not fetch subscription status (${response.statusCode}).');
    }
    return SubscriptionStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// TEMPORARY: records a subscription without real App Store/Play Store
  /// receipt verification — see matching.views.SubscriptionActivateView.
  Future<SubscriptionStatus> activateSubscription({
    required String deviceId,
    required String status,
    required DateTime startDate,
    required DateTime expiryDate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/subscription/activate/'),
      headers: _headers,
      body: jsonEncode({
        'device_id': deviceId,
        'status': status,
        'start_date': startDate.toIso8601String(),
        'expiry_date': expiryDate.toIso8601String(),
      }),
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not activate subscription (${response.statusCode}).');
    }
    return SubscriptionStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See notifications.views.NotificationListView. Notifications fire from
  /// real events (a subscription activating, a provider search turning up
  /// providers this device hasn't seen before) — there's no synthetic seed
  /// data, so a fresh device with no activity yet will legitimately see none.
  Future<NotificationsResult> getNotifications(String deviceId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications/?device_id=$deviceId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not fetch notifications (${response.statusCode}).');
    }
    return NotificationsResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> markNotificationsRead(String deviceId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/notifications/mark-read/'),
      headers: _headers,
      body: jsonEncode({'device_id': deviceId}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not mark notifications read (${response.statusCode}).');
    }
  }

  /// See provider_search.views.ProviderMatchListView — every provider this
  /// device has unlocked, each with its own request-pipeline status.
  Future<List<ProviderMatchRecord>> getProviderMatches(String deviceId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/provider-matches/?device_id=$deviceId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not fetch request history (${response.statusCode}).');
    }
    final matches = jsonDecode(response.body)['matches'] as List<dynamic>;
    return matches.map((m) => ProviderMatchRecord.fromJson(m as Map<String, dynamic>)).toList();
  }

  /// See provider_search.views.ProviderMatchStatusView.
  Future<ProviderMatchRecord> updateProviderMatchStatus({
    required String deviceId,
    required int matchId,
    required String status,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/provider-matches/$matchId/status/'),
      headers: _headers,
      body: jsonEncode({'device_id': deviceId, 'status': status}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not update request status (${response.statusCode}).');
    }
    return ProviderMatchRecord.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See provider_search.views.ProviderIncomingRequestListView — the
  /// authenticated provider's queue of requests still waiting on them
  /// (status "requested"). Same ProviderMatchSerializer shape the client's
  /// own "Your requests" history uses (see ProviderMatchRecord); it never
  /// includes device_id, so it's safe to show a provider.
  Future<List<ProviderMatchRecord>> getIncomingProviderRequests(String accessToken) async {
    final response = await http.get(
      Uri.parse('$baseUrl/provider/requests/'),
      headers: _authHeaders(accessToken),
    );
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not load incoming requests.');
    }
    final requests = jsonDecode(response.body)['requests'] as List<dynamic>;
    return requests.map((r) => ProviderMatchRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// See provider_search.views.ProviderRequestRespondView. `decision` must
  /// be [ProviderDecision.accepted] or [ProviderDecision.declined] — the
  /// only place a request moves out of "Requested", and the only way the
  /// client ever finds out a provider replied (it fires a notification —
  /// see notifications.services.notify).
  Future<ProviderMatchRecord> respondToProviderRequest({
    required String accessToken,
    required int requestId,
    required String decision,
    String message = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/provider/requests/$requestId/respond/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'decision': decision, if (message.isNotEmpty) 'message': message}),
    );
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not respond to that request.');
    }
    return ProviderMatchRecord.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See provider_search.views.ChatRefineView — free-text alternative to the
  /// fixed category-tap onboarding flow.
  Future<ChatRefineResult> refineChatMessage({
    required String message,
    required String deviceId,
    String city = ApiClient.demoCity,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/refine/'),
      headers: _headers,
      body: jsonEncode({'message': message, 'device_id': deviceId, 'city': city}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not process that message (${response.statusCode}).');
    }
    return ChatRefineResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See provider_search.views.KnownProvidersView — backs the demo Provider
  /// Dashboard's "sign in as" picker (no real provider accounts exist yet).
  Future<List<KnownProvider>> getKnownProviders() async {
    final response = await http.get(Uri.parse('$baseUrl/providers/known/'), headers: _headers);
    if (response.statusCode != 200) {
      throw ApiException('Could not load providers (${response.statusCode}).');
    }
    final providers = jsonDecode(response.body)['providers'] as List<dynamic>;
    return providers.map((p) => KnownProvider.fromJson(p as Map<String, dynamic>)).toList();
  }

  /// See provider_search.views.ProviderAvailabilityView.
  Future<bool> getProviderAvailability(String placeId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/provider-availability/?place_id=$placeId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not load availability (${response.statusCode}).');
    }
    return jsonDecode(response.body)['is_available_now'] as bool? ?? true;
  }

  Future<bool> setProviderAvailability({required String placeId, required bool isAvailableNow}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/provider-availability/'),
      headers: _headers,
      body: jsonEncode({'place_id': placeId, 'is_available_now': isAvailableNow}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not update availability (${response.statusCode}).');
    }
    return jsonDecode(response.body)['is_available_now'] as bool? ?? isAvailableNow;
  }

  /// See provider_search.views.ProviderOnboardingView.
  Future<ProviderOnboarding> getProviderOnboarding(String providerId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/provider-onboarding/?provider_id=$providerId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not load onboarding progress (${response.statusCode}).');
    }
    return ProviderOnboarding.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ProviderOnboarding> saveProviderOnboardingSection({
    required String providerId,
    required String section,
    required Map<String, dynamic> fields,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/provider-onboarding/'),
      headers: _headers,
      body: jsonEncode({'provider_id': providerId, 'section': section, 'fields': fields}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not save that section (${response.statusCode}).');
    }
    return ProviderOnboarding.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See accounts.views.RegisterView. Returns tokens immediately
  /// (auto-login), same as login.
  Future<AuthTokens> register({
    required String email,
    required String password,
    required String role,
    String fullName = '',
    String businessName = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/accounts/register/'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'role': role,
        'full_name': fullName,
        'business_name': businessName,
      }),
    );
    if (response.statusCode != 201) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not create that account.');
    }
    return AuthTokens.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See accounts.views.LoginView.
  Future<AuthTokens> login({required String email, required String password}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/accounts/login/'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Incorrect email or password.');
    }
    return AuthTokens.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See accounts.views.MeView.
  Future<AccountProfile> getMe(String accessToken) async {
    final response = await http.get(
      Uri.parse('$baseUrl/accounts/me/'),
      headers: _authHeaders(accessToken),
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not load your account (${response.statusCode}).');
    }
    return AccountProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See accounts.views.ProviderProfileView.
  Future<ProviderBusinessProfile> getProviderBusinessProfile(String accessToken) async {
    final response = await http.get(
      Uri.parse('$baseUrl/accounts/provider-profile/'),
      headers: _authHeaders(accessToken),
    );
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not load your business profile.');
    }
    return ProviderBusinessProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ProviderBusinessProfile> updateProviderBusinessProfile({
    required String accessToken,
    required Map<String, dynamic> fields,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/accounts/provider-profile/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode(fields),
    );
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not save your business profile.');
    }
    return ProviderBusinessProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See catalog.views.CategoryListView — the admin-managed
  /// category -> services tree behind the dynamic categories page (Phase
  /// 1B). Returns the parsed groups directly; callers that just need the
  /// flat, cached list should go through `loadCatalogFromApi` in
  /// onboarding/service_category.dart instead of calling this repeatedly.
  Future<List<ServiceCategoryGroup>> getCatalog() async {
    final response = await http.get(Uri.parse('$baseUrl/catalog/categories/'), headers: _headers);
    if (response.statusCode != 200) {
      throw ApiException('Could not load categories (${response.statusCode}).');
    }
    final categories = jsonDecode(response.body) as List<dynamic>;
    return categories.map((c) {
      final json = c as Map<String, dynamic>;
      final services = (json['services'] as List<dynamic>).map((s) {
        final serviceJson = s as Map<String, dynamic>;
        return ServiceCategory(
          label: serviceJson['name'] as String? ?? '',
          icon: iconForName(serviceJson['icon_name'] as String? ?? ''),
          whatWeCover: serviceJson['what_we_cover'] as String? ?? '',
          workerNoun: serviceJson['worker_noun'] as String? ?? '',
          slug: serviceJson['slug'] as String? ?? '',
        );
      }).toList();
      return ServiceCategoryGroup(
        label: json['name'] as String? ?? '',
        icon: iconForName(json['icon_name'] as String? ?? ''),
        slug: json['slug'] as String? ?? '',
        services: services,
      );
    }).toList();
  }

  // DRF validation errors come back as {"field": ["message"], ...} or
  // {"detail": "message"} — this pulls out something readable for either
  // shape rather than surfacing a raw status code to the user.
  String? _firstErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['detail'] is String) return decoded['detail'] as String;
      for (final value in decoded.values) {
        if (value is List && value.isNotEmpty) return value.first.toString();
        if (value is String) return value;
      }
    } catch (_) {
      // Not JSON — fall through to null so callers use their own default.
    }
    return null;
  }
}

class KnownProvider {
  const KnownProvider({required this.placeId, required this.name});

  factory KnownProvider.fromJson(Map<String, dynamic> json) {
    return KnownProvider(
      placeId: json['place_id'] as String,
      name: json['provider_name'] as String? ?? '',
    );
  }

  final String placeId;
  final String name;
}
