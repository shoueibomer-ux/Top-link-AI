import 'auth_models.dart';

/// The cities a provider can serve (provider_search.services.CITIES).
const kProviderCities = ['Edmonton', 'Calgary', 'Fort McMurray', 'Red Deer'];

enum ProviderStatus {
  pending,
  approved,
  rejected;

  static ProviderStatus parse(String? value) => ProviderStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => ProviderStatus.pending,
      );
}

/// A provider's own profile, from providers.serializers.ProviderProfileSerializer.
/// `categories` are catalog service slugs.
class ProviderProfileData {
  const ProviderProfileData({
    required this.businessName,
    required this.phone,
    required this.email,
    required this.categories,
    required this.cities,
    this.bio = '',
    this.smsConsent = false,
    this.status = ProviderStatus.pending,
    this.reviewNote = '',
  });

  factory ProviderProfileData.fromJson(Map<String, dynamic> json) {
    return ProviderProfileData(
      businessName: json['business_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      categories: [for (final c in json['categories'] as List<dynamic>? ?? const []) c as String],
      cities: [for (final c in json['cities'] as List<dynamic>? ?? const []) c as String],
      bio: json['bio'] as String? ?? '',
      status: ProviderStatus.parse(json['status'] as String?),
      reviewNote: json['review_note'] as String? ?? '',
    );
  }

  final String businessName;
  final String phone;
  final String email;
  final List<String> categories;
  final List<String> cities;
  final String bio;

  /// The "you may text me about client requests" checkbox. Only sent when
  /// registering; the server never returns it and ignores it on edits.
  final bool smsConsent;
  final ProviderStatus status;
  final String reviewNote;

  /// What the app sends. Status and review note are the admin's to set.
  Map<String, dynamic> toJson() => {
        'business_name': businessName,
        'phone': phone,
        'email': email,
        'categories': categories,
        'cities': cities,
        'bio': bio,
        if (smsConsent) 'sms_consent': true,
      };
}

/// The answer to POST /api/provider/auth/google/.
class ProviderSignIn {
  const ProviderSignIn({
    required this.tokens,
    required this.email,
    required this.fullName,
    required this.isNewAccount,
    this.profile,
  });

  factory ProviderSignIn.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'];
    return ProviderSignIn(
      tokens: AuthTokens.fromJson(json),
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      isNewAccount: json['is_new_account'] as bool? ?? false,
      profile: profile is Map<String, dynamic> ? ProviderProfileData.fromJson(profile) : null,
    );
  }

  final AuthTokens tokens;
  final String email;
  final String fullName;
  final bool isNewAccount;

  /// Null until the provider has registered.
  final ProviderProfileData? profile;
}

enum LeadStatus {
  awaitingReply,
  accepted,
  declined,
  expired;

  static LeadStatus parse(String? value) => switch (value) {
        'accepted' => LeadStatus.accepted,
        'declined' => LeadStatus.declined,
        'expired' => LeadStatus.expired,
        _ => LeadStatus.awaitingReply,
      };
}

/// One client request offered to the provider (providers.serializers.
/// ProviderLeadSerializer). The description and client name only come once the
/// provider has accepted; the client's phone number is never in the list.
class ProviderLead {
  const ProviderLead({
    required this.offerId,
    required this.requestId,
    required this.serviceSlug,
    required this.serviceName,
    required this.city,
    required this.status,
    this.urgency = '',
    this.sentAt,
    this.hired = false,
    this.jobCompleted = false,
    this.description,
    this.clientName,
  });

  factory ProviderLead.fromJson(Map<String, dynamic> json) {
    final service = json['service'] as Map<String, dynamic>? ?? const {};
    return ProviderLead(
      offerId: json['offer_id'] as int,
      requestId: json['request_id'] as int,
      serviceSlug: service['slug'] as String? ?? '',
      serviceName: service['name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      urgency: json['urgency'] as String? ?? '',
      status: LeadStatus.parse(json['status'] as String?),
      sentAt: DateTime.tryParse(json['sent_at'] as String? ?? ''),
      hired: json['hired'] as bool? ?? false,
      jobCompleted: json['job_completed'] as bool? ?? false,
      description: json['description'] as String?,
      clientName: json['client_name'] as String?,
    );
  }

  final int offerId;
  final int requestId;
  final String serviceSlug;
  final String serviceName;
  final String city;
  final String urgency;
  final LeadStatus status;
  final DateTime? sentAt;
  final bool hired;
  final bool jobCompleted;
  final String? description;
  final String? clientName;
}
