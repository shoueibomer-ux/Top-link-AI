/// One request the client has submitted — see
/// provider_search.views.ServiceRequestCreateView / ServiceRequestListView.
/// Replaces RealProvider/ProviderMatchRecord: there's no provider matching
/// yet, just the record of the request itself.
class ServiceRequestRecord {
  const ServiceRequestRecord({
    required this.id,
    required this.category,
    required this.city,
    required this.problemDescription,
    required this.phone,
    required this.status,
    required this.createdAt,
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
    );
  }

  final int id;
  final String category;
  final String city;
  final String problemDescription;
  final String phone;
  final String status;
  final DateTime createdAt;
}

/// Response from ChatRefineView — a classification only, no request created
/// yet (see ApiClient.createServiceRequest for that).
class ChatRefineResult {
  const ChatRefineResult({required this.category, required this.urgency, required this.notes});

  factory ChatRefineResult.fromJson(Map<String, dynamic> json) {
    return ChatRefineResult(
      category: json['category'] as String?,
      urgency: json['urgency'] as String? ?? 'exploring',
      notes: json['notes'] as String? ?? '',
    );
  }

  // Null means neither the AI call nor keyword matching could identify a
  // supported category — the UI should ask the client to rephrase.
  final String? category;
  final String urgency;
  final String notes;
}
