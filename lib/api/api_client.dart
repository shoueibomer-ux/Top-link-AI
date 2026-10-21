import 'dart:convert';

import 'package:http/http.dart' as http;

import '../onboarding/service_category.dart';
import 'api_config.dart';
import 'app_notification.dart';
import 'auth_models.dart';
import 'category_suggestions.dart';
import 'messaging.dart';
import 'provider_onboarding.dart';
import 'provider_profile.dart';
import 'reviews.dart';
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

/// The server says this person has to agree to the chat rules before they can send anything.
class ChatTermsRequired extends ApiException {
  ChatTermsRequired() : super('Agree to the chat rules first.');
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
    required String accessToken,
    required String category,
    required String phone,
    required bool consent,
    String deviceId = '',
    String city = ApiClient.demoCity,
    String description = '',
    String urgency = '',
    String location = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/requests/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({
        'device_id': deviceId,
        'category': category,
        'phone': phone,
        'consent': consent,
        'city': city,
        'description': description,
        'urgency': urgency,
        'location': location,
      }),
    );
    _throwForAuthProblems(response);
    if (response.statusCode != 201) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not submit your request.');
    }
    return ServiceRequestSubmission.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See provider_search.views.ServiceRequestListView: "Your requests", for the
  /// signed-in client only (there is no longer a way to list by device id).
  Future<List<ServiceRequestRecord>> getMyServiceRequests(String accessToken) async {
    final response = await http.get(
      Uri.parse('$baseUrl/requests/mine/'),
      headers: _authHeaders(accessToken),
    );
    _throwForAuthProblems(response);
    if (response.statusCode != 200) {
      throw ApiException('Could not fetch your requests (${response.statusCode}).');
    }
    final requests = jsonDecode(response.body)['requests'] as List<dynamic>;
    return requests.map((r) => ServiceRequestRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// See provider_search.views.ServiceRequestCompleteView: the client says the
  /// job with [offerId] (a provider who accepted) is done.
  Future<ServiceRequestRecord> completeServiceRequest(String accessToken, int requestId, int offerId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/requests/$requestId/complete/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'offer_id': offerId}),
    );
    _throwForAuthProblems(response);
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not mark the job complete (${response.statusCode}).');
    }
    return ServiceRequestRecord.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See accounts.views.ClientGoogleSignInView: trades a Google ID token for
  /// this client's own tokens.
  Future<ClientSignIn> signInClientWithGoogle(String idToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/accounts/google/'),
      headers: _headers,
      body: jsonEncode({'id_token': idToken}),
    );
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not sign in (${response.statusCode}).');
    }
    return ClientSignIn.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See providers.views.ProviderLeadsView: the requests offered to this provider.
  Future<List<ProviderLead>> getProviderLeads(String accessToken) async {
    final response = await http.get(Uri.parse('$baseUrl/provider/leads/'), headers: _authHeaders(accessToken));
    _throwForAuthProblems(response);
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not load your leads (${response.statusCode}).');
    }
    final leads = jsonDecode(response.body)['leads'] as List<dynamic>;
    return [for (final l in leads) ProviderLead.fromJson(l as Map<String, dynamic>)];
  }

  /// See notifications.views.NotificationListView. Notifications fire from
  /// real events — there's no synthetic seed data, so a fresh device with
  /// no activity yet will legitimately see none.
  /// The provider answers a lead from its card: the same as replying YES / NO to the text. Returns the lead as it
  /// is now (an accepted one includes the client's name and description).
  Future<ProviderLead> respondToLead(String accessToken, int offerId, {required bool accept}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/provider/leads/$offerId/${accept ? 'accept' : 'decline'}/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({}),
    );
    _throwForAuthProblems(response);
    if (response.statusCode != 200) {
      throw ApiException(
        _firstErrorMessage(response.body) ?? 'Could not ${accept ? 'accept' : 'decline'} this request (${response.statusCode}).',
      );
    }
    return ProviderLead.fromJson((jsonDecode(response.body) as Map<String, dynamic>)['lead'] as Map<String, dynamic>);
  }

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

  // ---- chat (the messaging app) --------------------------------------------------------------

  Map<String, dynamic> _chatBody(http.Response response, String failure) {
    // The "agree to the chat rules" answer is a 403 too, so it is recognised before the general 403 handling.
    if (response.statusCode == 403) {
      final decoded = _tryDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['code'] == 'terms_required') throw ChatTermsRequired();
    }
    _throwForAuthProblems(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_firstErrorMessage(response.body) ?? '$failure (${response.statusCode}).');
    }
    final decoded = _tryDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// This person's chats with unread counts, newest first.
  Future<({List<ChatConversation> conversations, int totalUnread})> getConversations(String accessToken) async {
    final response = await http.get(Uri.parse('$baseUrl/conversations/'), headers: _authHeaders(accessToken));
    final body = _chatBody(response, 'Could not load your chats');
    return (
      conversations: [
        for (final c in body['conversations'] as List<dynamic>? ?? const []) ChatConversation.fromJson(c as Map<String, dynamic>),
      ],
      totalUnread: body['total_unread'] as int? ?? 0,
    );
  }

  /// Starts (or returns) the chat for an offer a provider accepted.
  Future<ChatConversation> openConversation(String accessToken, int offerId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/open/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'offer_id': offerId}),
    );
    return ChatConversation.fromJson(_chatBody(response, 'Could not open the chat'));
  }

  /// The latest messages, or only those after [sinceId] (what the screen polls with).
  Future<ChatPage> getMessages(String accessToken, int conversationId, {int? sinceId}) async {
    final uri = Uri.parse('$baseUrl/conversations/$conversationId/messages/')
        .replace(queryParameters: {'since_id': ?sinceId?.toString()});
    final response = await http.get(uri, headers: _authHeaders(accessToken));
    return ChatPage.fromJson(_chatBody(response, 'Could not load the messages'));
  }

  Future<ChatMessage> sendMessage(String accessToken, int conversationId, {String body = '', String? photoKey}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/$conversationId/messages/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'body': body, 'photo_key': ?photoKey}),
    );
    return ChatMessage.fromJson(_chatBody(response, 'Could not send the message'));
  }

  Future<void> markConversationRead(String accessToken, int conversationId, {int? lastId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/$conversationId/read/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'last_id': ?lastId}),
    );
    _chatBody(response, 'Could not update the chat');
  }

  Future<String> getChatTerms(String accessToken) async {
    final response = await http.get(Uri.parse('$baseUrl/messaging/terms/'), headers: _authHeaders(accessToken));
    return _chatBody(response, 'Could not load the chat rules')['text'] as String? ?? '';
  }

  Future<void> acceptChatTerms(String accessToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/messaging/terms/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({}),
    );
    _chatBody(response, 'Could not save your choice');
  }

  /// A signed link to upload one photo, then [uploadPhotoBytes] sends it there.
  Future<PhotoUpload> requestPhotoUpload(String accessToken, int conversationId, String contentType) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/$conversationId/photos/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'content_type': contentType}),
    );
    return PhotoUpload.fromJson(_chatBody(response, 'Could not start the upload'));
  }

  /// Sends the photo straight to storage. Deliberately carries neither our API key nor the login token:
  /// that address is a third party's, and the signed link is all it needs.
  Future<void> uploadPhotoBytes(PhotoUpload upload, List<int> bytes) async {
    final response = await http.put(Uri.parse(upload.uploadUrl), headers: upload.headers, body: bytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('The photo could not be uploaded (${response.statusCode}). Try again.');
    }
  }

  Future<void> reportMessage(String accessToken, int conversationId, int messageId, String reason) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/$conversationId/messages/$messageId/report/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'reason': reason}),
    );
    _chatBody(response, 'Could not send your report');
  }

  Future<void> setConversationBlocked(String accessToken, int conversationId, bool blocked) async {
    final uri = Uri.parse('$baseUrl/conversations/$conversationId/block/');
    final response = blocked
        ? await http.post(uri, headers: _authHeaders(accessToken), body: jsonEncode({}))
        : await http.delete(uri, headers: _authHeaders(accessToken), body: jsonEncode({}));
    _chatBody(response, 'Could not update the block');
  }

  Future<CallInfo> getCallInfo(String accessToken, int conversationId) async {
    final response = await http.get(Uri.parse('$baseUrl/conversations/$conversationId/call/'), headers: _authHeaders(accessToken));
    return CallInfo.fromJson(_chatBody(response, 'Could not start the call'));
  }

  /// Tells the server this phone can receive this person's push notifications.
  Future<void> registerDevice(String accessToken, String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/devices/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'token': token, 'platform': 'android'}),
    );
    _chatBody(response, 'Could not register for notifications');
  }

  Future<void> unregisterDevice(String accessToken, String token) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/devices/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'token': token}),
    );
    _chatBody(response, 'Could not unregister');
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
  // ---- Provider self-registration (the providers app) ----------------------

  /// See providers.views.GoogleSignInView: trades a Google ID token for this
  /// provider's own tokens and, if they've registered, their profile.
  Future<ProviderSignIn> signInProviderWithGoogle(String idToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/provider/auth/google/'),
      headers: _headers,
      body: jsonEncode({'id_token': idToken}),
    );
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not sign in (${response.statusCode}).');
    }
    return ProviderSignIn.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// See providers.views.ProviderProfileView. Null until they've registered.
  Future<ProviderProfileData?> getMyProviderProfile(String accessToken) async {
    final response = await http.get(Uri.parse('$baseUrl/provider/profile/'), headers: _authHeaders(accessToken));
    if (response.statusCode == 404) return null;
    _throwForAuthProblems(response);
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not load your profile (${response.statusCode}).');
    }
    return ProviderProfileData.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Registers the profile; it starts as pending review.
  Future<ProviderProfileData> registerProviderProfile(String accessToken, ProviderProfileData data) async {
    final response = await http.post(
      Uri.parse('$baseUrl/provider/profile/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode(data.toJson()),
    );
    _throwForAuthProblems(response);
    if (response.statusCode != 201) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not submit your details (${response.statusCode}).');
    }
    return ProviderProfileData.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ProviderProfileData> updateMyProviderProfile(String accessToken, ProviderProfileData data) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/provider/profile/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode(data.toJson()),
    );
    _throwForAuthProblems(response);
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not save your changes (${response.statusCode}).');
    }
    return ProviderProfileData.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// SimpleJWT's refresh: a new access token (and, since refresh tokens
  /// rotate, usually a new refresh token) for a still-valid refresh token.
  Future<AuthTokens> refreshTokens(String refreshToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/accounts/token/refresh/'),
      headers: _headers,
      body: jsonEncode({'refresh': refreshToken}),
    );
    if (response.statusCode == 401) throw SessionExpiredException();
    if (response.statusCode != 200) {
      throw ApiException('Could not renew your session (${response.statusCode}).');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return AuthTokens(access: json['access'] as String, refresh: json['refresh'] as String? ?? refreshToken);
  }

  // ---- deleting the account ---------------------------------------------------------------------

  /// Deletes the signed-in person's own account (see accounts.deletion for what goes and what is kept).
  /// [confirm] is the word they typed. Afterwards the access token no longer works.
  Future<void> deleteMyAccount(String accessToken, {required String confirm}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/accounts/delete/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'confirm': confirm}),
    );
    _throwForAuthProblems(response);
    if (response.statusCode != 200) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'Could not delete your account (${response.statusCode}).');
    }
  }

  // ---- reviews and favorites (the reviews app) -----------------------------------------------

  Map<String, dynamic> _reviewBody(http.Response response, String failure) {
    _throwForAuthProblems(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_firstErrorMessage(response.body) ?? '$failure (${response.statusCode}).');
    }
    final decoded = _tryDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  /// The client rates the provider they hired, once the job is marked complete.
  Future<Review> submitReview(String accessToken, int offerId, int rating, String comment) async {
    final response = await http.post(
      Uri.parse('$baseUrl/offers/$offerId/review/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'rating': rating, 'comment': comment}),
    );
    return Review.fromJson(_reviewBody(response, 'Could not save your review'));
  }

  /// Changes the client's review (allowed for 7 days after posting).
  Future<Review> updateReview(String accessToken, int offerId, int rating, String comment) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/offers/$offerId/review/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'rating': rating, 'comment': comment}),
    );
    return Review.fromJson(_reviewBody(response, 'Could not save your review'));
  }

  /// A provider's public page: details, rating, reviews, and whether this client saved them.
  Future<ProviderPage> getProviderPage(String accessToken, int providerId) async {
    final response = await http.get(Uri.parse('$baseUrl/providers/$providerId/reviews/'), headers: _authHeaders(accessToken));
    return ProviderPage.fromJson(_reviewBody(response, 'Could not load this provider'));
  }

  /// The signed-in provider's own rating and reviews.
  Future<MyReviews> getMyReviews(String accessToken) async {
    final response = await http.get(Uri.parse('$baseUrl/provider/reviews/'), headers: _authHeaders(accessToken));
    return MyReviews.fromJson(_reviewBody(response, 'Could not load your reviews'));
  }

  /// The provider's one public reply to a review.
  Future<Review> replyToReview(String accessToken, int reviewId, String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reviews/$reviewId/reply/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'text': text}),
    );
    return Review.fromJson(_reviewBody(response, 'Could not post your reply'));
  }

  Future<void> reportReview(String accessToken, int reviewId, String reason) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reviews/$reviewId/report/'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'reason': reason}),
    );
    _reviewBody(response, 'Could not send your report');
  }

  Future<List<PublicProviderInfo>> getFavorites(String accessToken) async {
    final response = await http.get(Uri.parse('$baseUrl/favorites/'), headers: _authHeaders(accessToken));
    final body = _reviewBody(response, 'Could not load your favorites');
    return [for (final f in body['favorites'] as List<dynamic>? ?? const []) PublicProviderInfo.fromJson(f as Map<String, dynamic>)];
  }

  Future<void> setFavorite(String accessToken, int providerId, bool favorite) async {
    final uri = Uri.parse('$baseUrl/favorites/$providerId/');
    final response = favorite
        ? await http.put(uri, headers: _authHeaders(accessToken), body: jsonEncode({}))
        : await http.delete(uri, headers: _authHeaders(accessToken), body: jsonEncode({}));
    _reviewBody(response, 'Could not update your favorites');
  }

  /// A 401 normally means the access token expired, but it is also how the
  /// server rejects a wrong API key. Only the first is something signing in
  /// again would fix.
  void _throwForAuthProblems(http.Response response) {
    if (response.statusCode == 401) {
      final message = _firstErrorMessage(response.body) ?? '';
      if (message.toLowerCase().contains('api key')) throw ApiException(message);
      throw SessionExpiredException();
    }
    if (response.statusCode == 403) {
      throw ApiException(_firstErrorMessage(response.body) ?? 'This account cannot do that.');
    }
  }

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
