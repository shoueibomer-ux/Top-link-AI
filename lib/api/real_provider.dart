/// A real business returned by GET /api/providers/search/
/// (provider_search.views.ProviderSearchView) — backed by Google Places,
/// not the seed-data matching engine.
class RealProvider {
  const RealProvider({
    required this.name,
    required this.phone,
    this.placeId,
    this.city,
    this.address,
    this.website,
    this.mapsUrl,
    this.rating,
    this.ratingCount,
    this.recentContactCount = 0,
    this.isAvailableNow = true,
    this.estimatedResponseMinutes,
    this.isUnlocked = false,
  });

  factory RealProvider.fromJson(Map<String, dynamic> json) {
    return RealProvider(
      placeId: json['place_id'] as String?,
      name: json['name'] as String? ?? '',
      city: json['city'] as String?,
      address: json['address'] as String?,
      phone: json['phone'] as String? ?? '',
      website: json['website'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      ratingCount: json['rating_count'] as int?,
      mapsUrl: json['maps_url'] as String?,
      recentContactCount: json['recent_contact_count'] as int? ?? 0,
      isAvailableNow: json['is_available_now'] as bool? ?? true,
      estimatedResponseMinutes: json['estimated_response_minutes'] as int?,
      isUnlocked: json['is_unlocked'] as bool? ?? false,
    );
  }

  final String? placeId;
  final String name;

  // Always present — free/descriptive info shown pre-unlock (see [isUnlocked]).
  final String? city;

  // Full contact details — null/masked until this device has unlocked this
  // specific provider (see [isUnlocked]). `phone` is never empty pre-unlock:
  // the backend sends a masked string like "+1 780-904-XXXX" rather than
  // omitting it, so it's always safe to display as-is.
  final String? address;
  final String phone;
  final String? website;
  final String? mapsUrl;

  final double? rating;
  final int? ratingCount;

  // Distinct devices that have unlocked (or progressed further with) this
  // provider in the last week (see provider_search.services.recent_contact_counts)
  // — shown as social proof on the card, unlocked or not.
  final int recentContactCount;

  // This platform's own available-now/busy override (see
  // provider_search.models.ProviderAvailability) — not from Google Places.
  final bool isAvailableNow;

  // Placeholder "usually responds within N min" estimate — free/visible
  // regardless of unlock state (see provider_search.services.
  // estimated_response_minutes for why it's a placeholder, not a real
  // measurement).
  final int? estimatedResponseMinutes;

  // True once this device has unlocked this specific provider (paid $4.99
  // or used an active subscription — see provider_search.views.
  // ProviderUnlockView). Only then are [address]/[website]/[mapsUrl]
  // populated and [phone] the real number. Server-authoritative: the
  // backend decides this per place_id, never inferred client-side.
  final bool isUnlocked;

  bool get hasFullDetails => isUnlocked;
}

class ProviderSearchResult {
  const ProviderSearchResult({required this.isSubscribed, required this.providers});

  factory ProviderSearchResult.fromJson(Map<String, dynamic> json) {
    final providers = (json['providers'] as List<dynamic>)
        .map((p) => RealProvider.fromJson(p as Map<String, dynamic>))
        .toList();
    return ProviderSearchResult(
      isSubscribed: json['is_subscribed'] as bool? ?? false,
      providers: providers,
    );
  }

  // Whether this device currently has an active subscription — a hint for
  // the unlock prompt's copy (their next unlock is free either way; the
  // backend decides that server-side). Search results are masked/unlocked
  // per-provider regardless of this value — see RealProvider.isUnlocked.
  final bool isSubscribed;
  final List<RealProvider> providers;
}
