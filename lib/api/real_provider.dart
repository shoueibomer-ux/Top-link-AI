/// A real business returned by GET /api/providers/search/
/// (provider_search.views.ProviderSearchView) — backed by Google Places,
/// not the seed-data matching engine.
class RealProvider {
  const RealProvider({
    required this.name,
    required this.phone,
    this.placeId,
    this.address,
    this.website,
    this.rating,
    this.ratingCount,
    this.mapsUrl,
    this.recentContactCount = 0,
    this.isAvailableNow = true,
    this.estimatedResponseMinutes,
  });

  factory RealProvider.fromJson(Map<String, dynamic> json) {
    return RealProvider(
      placeId: json['place_id'] as String?,
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      phone: json['phone'] as String? ?? '',
      website: json['website'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      ratingCount: json['rating_count'] as int?,
      mapsUrl: json['maps_url'] as String?,
      recentContactCount: json['recent_contact_count'] as int? ?? 0,
      isAvailableNow: json['is_available_now'] as bool? ?? true,
      estimatedResponseMinutes: json['estimated_response_minutes'] as int?,
    );
  }

  final String? placeId;
  final String name;
  final String? address;
  final String phone;
  final String? website;
  final double? rating;
  final int? ratingCount;
  final String? mapsUrl;

  // Distinct devices that marked this provider "contacted" or further in
  // the last week (see provider_search.services.recent_contact_counts) —
  // shown as social proof on the card, before or after subscribing.
  final int recentContactCount;

  // This platform's own available-now/busy override (see
  // provider_search.models.ProviderAvailability) — not from Google Places.
  final bool isAvailableNow;

  // Placeholder "usually responds within N min" estimate — only present
  // once this device has unlocked the provider's full contact info (see
  // provider_search.services.estimated_response_minutes for why it's a
  // placeholder, not a real measurement).
  final int? estimatedResponseMinutes;

  // Address (and website/maps link) are only included once the device is
  // subscribed — see ProviderSearchResult.subscriptionRequired. Unsubscribed
  // previews carry just name/rating/masked phone.
  bool get hasFullDetails => address != null;
}

class ProviderSearchResult {
  const ProviderSearchResult({required this.subscriptionRequired, required this.providers});

  factory ProviderSearchResult.fromJson(Map<String, dynamic> json) {
    final providers = (json['providers'] as List<dynamic>)
        .map((p) => RealProvider.fromJson(p as Map<String, dynamic>))
        .toList();
    return ProviderSearchResult(
      subscriptionRequired: json['subscription_required'] as bool? ?? false,
      providers: providers,
    );
  }

  final bool subscriptionRequired;
  final List<RealProvider> providers;
}
