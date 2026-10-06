import 'dart:convert';

import 'package:http/http.dart' as http;

import '../onboarding/service_category.dart';
import 'api_config.dart';
import 'app_notification.dart';
import 'auth_models.dart';
import 'category_suggestions.dart';
import 'provider_onboarding.dart';
import 'service_request.dart';

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when the backend answers 401 to a request carrying a Bearer token —
/// the access token expired or was revoked. Retrying can't help; the user has
/// to log in again, which is what callers should offer.
class SessionExpiredException extends ApiException {
  SessionExpiredException() : super('Your session has expired. Please log in again.');
}

class ApiClient {
  // The URL and API key come from ApiConfig (build-time --dart-define values;
  // release builds refuse a non-HTTPS URL or the dev key — see its class
  // doc). An explicit [baseUrl] is checked by the same rules.
  ApiClient({String? baseUrl}) : baseUrl = baseUrl == null ? ApiConfig.baseUrl() : ApiConfig.checkBaseUrl(baseUrl);

  final String baseUrl;

  // Demo location (Edmonton) used to prefill the location step. provider_search
  // only covers a fixed set of Alberta cities (see provider_search.services.CITIES),
  // so demoCity pins searches to the one matching the demo coordinates rather
  // than deriving a city from lat/lng.
  static const demoLat = 53.5444;
  static const demoLng = -113.4909;
  static const demoCity = 'Edmonton';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-API-Key': ApiConfig.apiKey(),
      };

  // Adds the Bearer token on top of the usual headers — every accounts.*
  // endpoint that reads/writes a specific account needs both: the shared
  // API key (the app-wide anti-scraping gate, same as every other endpoint)
  // and the token (who, specifically, is asking).
  Map<String, String> _authHeaders(String accessToken) => {
        ..._headers,
        'Authorization': 'Bearer $accessToken',
      };

  /// See provider_search.views.ServiceRequestCreateView — the only way a
  /// request is created, by this flow and (once it exists) the website
  /// form. `consent` must be true: explicit, per-request agreement to share
  /// the request (including `phone`) with providers — there is no default,
  /// callers must have actually shown the consent copy and had it checked.
  Future<ServiceRequestSubmission> createServiceRequest({
    required String deviceId,
    required String category,
    required String phone,
    required bool consent,
    String city = ApiClient.demoCity,
    String description = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/requests/'),
      headers: _headers,
      body: jsonEncode({
        'device_id': deviceId,
        'category': category,
        'phone': phone,
        'consent': consent,
        'city': city,
        'description': description,
      }),
    );
    if (response.statusCode != 201) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not submit your request.');
    }
    return ServiceRequestSubmission.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See provider_search.views.ServiceRequestListView — "Your requests".
  Future<List<ServiceRequestRecord>> getMyServiceRequests(String deviceId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/requests/mine/?device_id=$deviceId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not fetch your requests (${response.statusCode}).');
    }
    final requests = jsonDecode(response.body)['requests'] as List<dynamic>;
    return requests.map((r) => ServiceRequestRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// See notifications.views.NotificationListView. Notifications fire from
  /// real events — there's no synthetic seed data, so a fresh device with
  /// no activity yet will legitimately see none.
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

  /// See provider_search.views.ChatRefineView — free-text classification
  /// only (no request is created here; see [createServiceRequest]). Lets
  /// Ask AI tell the client what category it thinks they mean before they
  /// commit to anything.
  Future<ChatRefineResult> refineChatMessage({
    required String message,
    required String deviceId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/refine/'),
      headers: _headers,
      body: jsonEncode({'message': message, 'device_id': deviceId}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Could not process that message (${response.statusCode}).');
    }
    return ChatRefineResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See matching.views.CategorySuggestView — the category search bar's
  /// keyword lookup. Never an AI call, so it is fine to run as the user types.
  Future<RemoteCategorySuggestions> suggestCategories(String query) async {
    final uri = Uri.parse('$baseUrl/categories/suggest/').replace(
      // The app offers a waitlist for services that aren't open yet, so it
      // wants those suggested too.
      queryParameters: {'q': query, 'include_unlaunched': 'true'},
    );
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw ApiException('Could not load suggestions (${response.statusCode}).');
    }
    return RemoteCategorySuggestions.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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
    if (response.statusCode == 401) throw SessionExpiredException();
    if (response.statusCode != 200) {
      throw ApiException('Could not load your account (${response.statusCode}).');
    }
    return AccountProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// PATCH accounts.views.MeView — edits the signed-in user's own name and/or
  /// sign-in email (never role or password). Pass only what should change.
  /// Throws [ApiException] with the server's message for validation failures
  /// (e.g. an email already in use) and [SessionExpiredException] on 401.
  Future<AccountProfile> updateMe({
    required String accessToken,
    String? fullName,
    String? email,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/accounts/me/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({
        'full_name': ?fullName,
        'email': ?email,
      }),
    );
    if (response.statusCode == 401) throw SessionExpiredException();
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not save your changes.');
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
  ///
  /// By default only launched services come back (what clients see); pass
  /// [includeUnlaunched] for every active service — the provider pickers use
  /// it so providers can register in upcoming categories.
  Future<List<ServiceCategoryGroup>> getCatalog({bool includeUnlaunched = false}) async {
    final uri = Uri.parse('$baseUrl/catalog/categories/').replace(
      queryParameters: includeUnlaunched ? {'include_unlaunched': 'true'} : null,
    );
    final response = await http.get(uri, headers: _headers);
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
          isLaunched: serviceJson['is_launched'] as bool? ?? true,
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
