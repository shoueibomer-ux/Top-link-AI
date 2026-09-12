class ProviderProfile {
  const ProviderProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.categories,
    required this.rating,
  });

  factory ProviderProfile.fromJson(Map<String, dynamic> json) {
    return ProviderProfile(
      id: json['id'] as int,
      name: json['name'] as String,
      role: json['role'] as String,
      categories: (json['categories'] as List<dynamic>)
          .map((c) => (c as Map<String, dynamic>)['name'] as String)
          .toList(),
      rating: (json['rating'] as num).toDouble(),
    );
  }

  final int id;
  final String name;
  final String role;
  final List<String> categories;
  final double rating;
}

class MatchResult {
  const MatchResult({
    required this.profile,
    required this.score,
    required this.breakdown,
  });

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    return MatchResult(
      profile: ProviderProfile.fromJson(json['profile'] as Map<String, dynamic>),
      score: (json['score'] as num).toDouble(),
      breakdown: Map<String, dynamic>.from(json['breakdown'] as Map),
    );
  }

  final ProviderProfile profile;
  final double score;
  final Map<String, dynamic> breakdown;

  double get distanceKm => (breakdown['distance_km'] as num?)?.toDouble() ?? 0;
}
