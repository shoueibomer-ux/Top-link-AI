import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  /// provider_search.views.ProviderSearchView) — gated by the same
  /// device-based Subscription used everywhere else. Subscribed devices get
  /// full contact details; unsubscribed devices get a masked preview
  /// (RealProvider.hasFullDetails is false and result.subscriptionRequired
  /// is true), which in practice should only happen if a subscription
  /// lapses between the paywall check and this call, since AppEntryPoint
  /// already gates the rest of the app behind an active subscription.
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
