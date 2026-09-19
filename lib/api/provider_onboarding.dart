/// Mirrors provider_search.models.ProviderOnboarding.SECTION_FIELDS keys —
/// order matches the wizard's tab order.
class OnboardingSection {
  static const personalInfo = 'personal_info';
  static const services = 'services';
  static const serviceArea = 'service_area';
  static const credentials = 'credentials';
  static const photos = 'photos';

  static const all = [personalInfo, services, serviceArea, credentials, photos];

  static String label(String section) => switch (section) {
        personalInfo => 'Personal Info',
        services => 'Services Offered',
        serviceArea => 'Service Area',
        credentials => 'Credentials',
        photos => 'Photos',
        _ => section,
      };
}

/// A provider's structured sign-up progress, from
/// GET/POST /api/provider-onboarding/ (provider_search.views.ProviderOnboardingView).
class ProviderOnboarding {
  const ProviderOnboarding({
    required this.providerId,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.services,
    required this.city,
    required this.yearsExperience,
    required this.isInsured,
    required this.photoUrls,
    required this.completionPercentage,
    required this.isComplete,
    required this.sectionStatus,
  });

  factory ProviderOnboarding.fromJson(Map<String, dynamic> json) {
    return ProviderOnboarding(
      providerId: json['provider_id'] as String,
      fullName: json['full_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      services: (json['services'] as List<dynamic>? ?? []).cast<String>(),
      city: json['city'] as String? ?? '',
      yearsExperience: json['years_experience'] as int?,
      isInsured: json['is_insured'] as bool? ?? false,
      photoUrls: (json['photo_urls'] as List<dynamic>? ?? []).cast<String>(),
      completionPercentage: json['completion_percentage'] as int? ?? 0,
      isComplete: json['is_complete'] as bool? ?? false,
      sectionStatus: (json['section_status'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value as bool),
      ),
    );
  }

  final String providerId;
  final String fullName;
  final String phone;
  final String email;
  final List<String> services;
  final String city;
  final int? yearsExperience;
  final bool isInsured;
  final List<String> photoUrls;
  final int completionPercentage;
  final bool isComplete;
  final Map<String, bool> sectionStatus;

  bool isSectionComplete(String section) => sectionStatus[section] ?? false;
}
