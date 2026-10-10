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
