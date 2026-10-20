/// A provider's average rating and how many reviews it is made of (reviews.ratings). [average] is null until
/// the first review.
class RatingSummary {
  const RatingSummary({this.average, this.count = 0});

  factory RatingSummary.fromJson(Map<String, dynamic> json) {
    final avg = json['rating_average'];
    return RatingSummary(
      average: avg is num ? avg.toDouble() : null,
      count: json['review_count'] as int? ?? 0,
    );
  }

  final double? average;
  final int count;

  bool get hasReviews => count > 0 && average != null;
}

/// The provider's one public reply to a review.
class ReviewReply {
  const ReviewReply({required this.text, this.createdAt});

  factory ReviewReply.fromJson(Map<String, dynamic> json) => ReviewReply(
        text: json['text'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );

  final String text;
  final DateTime? createdAt;
}

/// One review (reviews.serializers.serialize_review). The client appears as "Pat P."; [canEdit] and
/// [editableUntil] only come for the author, who may change it for 7 days.
class Review {
  const Review({
    required this.id,
    required this.rating,
    required this.clientName,
    required this.createdAt,
    this.comment = '',
    this.edited = false,
    this.reply,
    this.mine = false,
    this.hidden = false,
    this.canEdit = false,
    this.editableUntil,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    final reply = json['reply'];
    return Review(
      id: json['id'] as int,
      rating: json['rating'] as int? ?? 0,
      comment: json['comment'] as String? ?? '',
      clientName: json['client_name'] as String? ?? 'A client',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      edited: json['edited'] as bool? ?? false,
      reply: reply is Map<String, dynamic> ? ReviewReply.fromJson(reply) : null,
      mine: json['mine'] as bool? ?? false,
      hidden: json['hidden'] as bool? ?? false,
      canEdit: json['can_edit'] as bool? ?? false,
      editableUntil: DateTime.tryParse(json['editable_until'] as String? ?? ''),
    );
  }

  final int id;
  final int rating;
  final String comment;
  final String clientName;
  final DateTime createdAt;
  final bool edited;
  final ReviewReply? reply;
  final bool mine;

  /// Hidden by a moderator. Only the author is ever sent a hidden review.
  final bool hidden;
  final bool canEdit;
  final DateTime? editableUntil;
}

/// What anyone may see of an approved provider (no phone, no email), with their rating.
class PublicProviderInfo {
  const PublicProviderInfo({
    required this.id,
    required this.businessName,
    this.bio = '',
    this.categories = const [],
    this.cities = const [],
    this.rating = const RatingSummary(),
  });

  factory PublicProviderInfo.fromJson(Map<String, dynamic> json) {
    return PublicProviderInfo(
      id: json['id'] as int,
      businessName: json['business_name'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      categories: [for (final c in json['categories'] as List<dynamic>? ?? const []) c as String],
      cities: [for (final c in json['cities'] as List<dynamic>? ?? const []) c as String],
      rating: RatingSummary.fromJson(json),
    );
  }

  final int id;
  final String businessName;
  final String bio;
  final List<String> categories;
  final List<String> cities;
  final RatingSummary rating;
}

/// GET /api/providers/{id}/reviews/ — a provider's public page.
class ProviderPage {
  const ProviderPage({required this.provider, required this.reviews, required this.isFavorite});

  factory ProviderPage.fromJson(Map<String, dynamic> json) {
    return ProviderPage(
      provider: PublicProviderInfo.fromJson(json['provider'] as Map<String, dynamic>? ?? const {'id': 0}),
      reviews: [for (final r in json['reviews'] as List<dynamic>? ?? const []) Review.fromJson(r as Map<String, dynamic>)],
      isFavorite: json['is_favorite'] as bool? ?? false,
    );
  }

  final PublicProviderInfo provider;
  final List<Review> reviews;
  final bool isFavorite;
}

/// GET /api/provider/reviews/ — the signed-in provider's own rating and reviews.
class MyReviews {
  const MyReviews({required this.summary, required this.reviews});

  factory MyReviews.fromJson(Map<String, dynamic> json) {
    return MyReviews(
      summary: RatingSummary.fromJson(json['summary'] as Map<String, dynamic>? ?? const {}),
      reviews: [for (final r in json['reviews'] as List<dynamic>? ?? const []) Review.fromJson(r as Map<String, dynamic>)],
    );
  }

  final RatingSummary summary;
  final List<Review> reviews;
}

/// The reasons a review can be reported for (reviews.models.ReviewReport.REASON_CHOICES).
const kReviewReportReasons = <String, String>{
  'spam': 'Spam or advertising',
  'abusive': 'Abusive or hateful',
  'fake': 'Fake or not a real customer',
  'personal': 'Shares personal information',
  'other': 'Something else',
};

const kMaxReviewChars = 1000;
