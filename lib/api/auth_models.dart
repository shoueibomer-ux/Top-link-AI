/// From POST /api/accounts/register/ or /api/accounts/login/ (SimpleJWT's
/// standard {access, refresh} pair — see accounts.views.LoginView).
class AuthTokens {
  const AuthTokens({required this.access, required this.refresh});

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      access: json['access'] as String,
      refresh: json['refresh'] as String,
    );
  }

  final String access;
  final String refresh;
}

/// Mirrors accounts.models.ProviderBusinessProfile /
/// ProviderBusinessProfileSerializer — the one permanent provider identity
/// per the marketplace build plan's Phase 1A.
class ProviderBusinessProfile {
  const ProviderBusinessProfile({
    required this.businessName,
    required this.description,
    required this.categories,
    required this.city,
    required this.phone,
    required this.isAvailableNow,
    required this.providerType,
    required this.teamSize,
    required this.equipment,
    required this.certifications,
    required this.serviceRadiusKm,
    required this.languages,
    required this.responseTimeMinutes,
    required this.completionRate,
    required this.placeId,
    required this.yearsExperience,
    required this.isInsured,
    required this.photoUrls,
    required this.rating,
    required this.ratingCount,
  });

  factory ProviderBusinessProfile.fromJson(Map<String, dynamic> json) {
    List<String> stringList(dynamic value) => (value as List<dynamic>? ?? []).cast<String>();

    return ProviderBusinessProfile(
      businessName: json['business_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      categories: stringList(json['categories']),
      city: json['city'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      isAvailableNow: json['is_available_now'] as bool? ?? true,
      providerType: json['provider_type'] as String? ?? ProviderType.individual,
      teamSize: json['team_size'] as int?,
      equipment: stringList(json['equipment']),
      certifications: stringList(json['certifications']),
      serviceRadiusKm: (json['service_radius_km'] as num?)?.toDouble(),
      languages: stringList(json['languages']),
      responseTimeMinutes: json['response_time_minutes'] as int?,
      completionRate: (json['completion_rate'] as num?)?.toDouble(),
      placeId: json['place_id'] as String?,
      yearsExperience: json['years_experience'] as int?,
      isInsured: json['is_insured'] as bool? ?? false,
      photoUrls: stringList(json['photo_urls']),
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: json['rating_count'] as int? ?? 0,
    );
  }

  final String businessName;
  final String description;
  final List<String> categories;
  final String city;
  final String phone;
  final bool isAvailableNow;
  final String providerType;
  final int? teamSize;
  final List<String> equipment;
  final List<String> certifications;
  final double? serviceRadiusKm;
  final List<String> languages;
  final int? responseTimeMinutes;
  final double? completionRate;
  final String? placeId;
  final int? yearsExperience;
  final bool isInsured;
  final List<String> photoUrls;
  final double rating;
  final int ratingCount;
}

class ProviderType {
  static const individual = 'individual';
  static const business = 'business';

  static const all = [individual, business];

  static String label(String value) => switch (value) {
        individual => 'Individual',
        business => 'Business',
        _ => value,
      };
}

/// Mirrors accounts.models.UserRole.
class UserRole {
  static const customer = 'customer';
  static const provider = 'provider';
  static const admin = 'admin';
}

/// From GET /api/accounts/me/ (accounts.serializers.UserProfileSerializer).
class AccountProfile {
  const AccountProfile({
    required this.email,
    required this.role,
    required this.fullName,
    required this.providerProfile,
  });

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    final providerProfileJson = json['provider_profile'] as Map<String, dynamic>?;
    return AccountProfile(
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? UserRole.customer,
      fullName: json['full_name'] as String? ?? '',
      providerProfile: providerProfileJson == null ? null : ProviderBusinessProfile.fromJson(providerProfileJson),
    );
  }

  final String email;
  final String role;
  final String fullName;
  final ProviderBusinessProfile? providerProfile;
}
