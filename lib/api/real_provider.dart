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
