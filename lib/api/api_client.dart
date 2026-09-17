import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
}
