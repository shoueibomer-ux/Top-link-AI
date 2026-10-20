import 'reviews.dart';

/// One request the client has submitted — see
/// provider_search.views.ServiceRequestCreateView / ServiceRequestListView.
/// Replaces RealProvider/ProviderMatchRecord: there's no provider matching
/// yet, just the record of the request itself.
/// A provider who said YES to a request, as the client sees them (see
/// provider_search.serializers.ServiceRequestSerializer.accepted_offers).
class AcceptedOffer {
  const AcceptedOffer({
    required this.offerId,
    required this.providerId,
    required this.providerName,
    this.hired = false,
    this.jobCompleted = false,
    this.canComplete = true,
    this.providerRating = const RatingSummary(),
    this.review,
    this.canReview = false,
  });

  factory AcceptedOffer.fromJson(Map<String, dynamic> json) {
    final provider = json['provider'] as Map<String, dynamic>? ?? const {};
    return AcceptedOffer(
      offerId: json['offer_id'] as int,
      providerId: provider['id'] as int? ?? 0,
      providerName: provider['business_name'] as String? ?? '',
      hired: json['hired'] as bool? ?? false,
      jobCompleted: json['job_completed'] as bool? ?? false,
      canComplete: json['can_complete'] as bool? ?? false,
      providerRating: RatingSummary.fromJson(provider),
      review: json['review'] is Map<String, dynamic> ? Review.fromJson(json['review'] as Map<String, dynamic>) : null,
      canReview: json['can_review'] as bool? ?? false,
    );
  }

  final int offerId;
  final int providerId;
  final String providerName;
  final bool hired;
  final bool jobCompleted;

  /// True only while no provider on this request has been marked completed.
  final bool canComplete;

  /// The provider's average rating and review count.
  final RatingSummary providerRating;

  /// The client's own review of this job, once written.
  final Review? review;

  /// The job is complete and the client hasn't reviewed it yet.
  final bool canReview;
}

class ServiceRequestRecord {
  const ServiceRequestRecord({
    required this.id,
    required this.category,
    required this.city,
    required this.problemDescription,
    required this.phone,
    required this.status,
    required this.createdAt,
    this.urgency = '',
    this.acceptedOffers = const [],
  });

  factory ServiceRequestRecord.fromJson(Map<String, dynamic> json) {
    return ServiceRequestRecord(
      id: json['id'] as int,
      category: json['category'] as String? ?? '',
      city: json['city'] as String? ?? '',
      problemDescription: json['problem_description'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      status: json['status'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      urgency: json['urgency'] as String? ?? '',
      acceptedOffers: [
        for (final o in json['accepted_offers'] as List<dynamic>? ?? const [])
          AcceptedOffer.fromJson(o as Map<String, dynamic>),
      ],
    );
  }

  final int id;
  final String category;
  final String city;
  final String problemDescription;
  final String phone;
  final String status;
  final DateTime createdAt;
  final String urgency;
  final List<AcceptedOffer> acceptedOffers;
}

/// Response from ChatRefineView — a classification only, no request created
/// yet (see ApiClient.createServiceRequest for that).
class ChatRefineResult {
  const ChatRefineResult({
    required this.category,
    required this.urgency,
    required this.notes,
    this.launched = true,
  });

  factory ChatRefineResult.fromJson(Map<String, dynamic> json) {
    return ChatRefineResult(
      category: json['category'] as String?,
      urgency: json['urgency'] as String? ?? 'exploring',
      notes: json['notes'] as String? ?? '',
      launched: json['launched'] as bool? ?? true,
    );
  }

  // Null means neither the AI call nor keyword matching could identify a
  // service — the UI should ask the client to rephrase.
  final String? category;
  final String urgency;
  final String notes;

  // False when the service exists but isn't launched yet — the UI says
  // "coming soon" instead of continuing into the request flow.
  final bool launched;
}

/// What ServiceRequestCreateView answered when a request was submitted.
class ServiceRequestSubmission {
  const ServiceRequestSubmission({required this.requestId, required this.status, this.message});

  factory ServiceRequestSubmission.fromJson(Map<String, dynamic> json) {
    return ServiceRequestSubmission(
      requestId: json['request_id'] as int,
      status: json['status'] as String? ?? 'new',
      message: json['message'] as String?,
    );
  }

  final int requestId;
  final String status;

  // Set when the service isn't launched yet ("Coming soon in your area").
  final String? message;

  bool get isWaitlisted => status == 'waitlisted';
}

/// Where a request stands, as the client sees it.
enum RequestStatus { waitlisted, waiting, accepted, completed }

RequestStatus requestStatusOf(ServiceRequestRecord request) {
  if (request.acceptedOffers.any((o) => o.jobCompleted)) return RequestStatus.completed;
  if (request.acceptedOffers.isNotEmpty) return RequestStatus.accepted;
  if (request.status == 'waitlisted') return RequestStatus.waitlisted;
  return RequestStatus.waiting;
}

/// "Waiting for a provider", "Accepted by Ace Plumbing" (or "Accepted by A and B", "Accepted by A, B and C"),
/// "Completed", or "Waitlisted" for a service that has not opened yet.
String requestStatusLabel(ServiceRequestRecord request) {
  switch (requestStatusOf(request)) {
    case RequestStatus.completed:
      return 'Completed';
    case RequestStatus.accepted:
      final names = [for (final o in request.acceptedOffers) o.providerName];
      final list = names.length == 1
          ? names.first
          : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
      return 'Accepted by $list';
    case RequestStatus.waitlisted:
      return 'Waitlisted';
    case RequestStatus.waiting:
      return 'Waiting for a provider';
  }
}
