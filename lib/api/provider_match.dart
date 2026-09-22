/// A client "request" — one device's engagement with one real provider —
/// returned by GET /api/provider-matches/ (provider_search.views.ProviderMatchListView).
/// Backed by the same ProviderMatch row Django uses for unlock tracking; the
/// `status` field is what turns it into a request/booking pipeline.
class ProviderMatchRecord {
  const ProviderMatchRecord({
    required this.id,
    required this.category,
    required this.city,
    required this.providerName,
    required this.providerPhone,
    required this.providerAddress,
    required this.providerWebsite,
    required this.problemDescription,
    required this.status,
    required this.providerDecision,
    required this.providerMessage,
    required this.respondedAt,
    required this.firstUnlockedAt,
    required this.lastViewedAt,
  });

  factory ProviderMatchRecord.fromJson(Map<String, dynamic> json) {
    final respondedAt = json['responded_at'] as String?;
    return ProviderMatchRecord(
      id: json['id'] as int,
      category: json['category'] as String? ?? '',
      city: json['city'] as String? ?? '',
      providerName: json['provider_name'] as String? ?? '',
      providerPhone: json['provider_phone'] as String? ?? '',
      providerAddress: json['provider_address'] as String? ?? '',
      providerWebsite: json['provider_website'] as String? ?? '',
      problemDescription: json['problem_description'] as String? ?? '',
      status: json['status'] as String? ?? ProviderMatchStatus.requested,
      providerDecision: json['provider_decision'] as String? ?? '',
      providerMessage: json['provider_message'] as String? ?? '',
      respondedAt: respondedAt == null ? null : DateTime.parse(respondedAt),
      firstUnlockedAt: DateTime.parse(json['first_unlocked_at'] as String),
      lastViewedAt: DateTime.parse(json['last_viewed_at'] as String),
    );
  }

  final int id;
  final String category;
  final String city;
  final String providerName;
  final String providerPhone;
  final String providerAddress;
  final String providerWebsite;
  // Only non-empty when this match came from the "Ask AI" chat flow — blank
  // for matches found via the fixed category-tap onboarding flow.
  final String problemDescription;
  final String status;
  // Set only once a provider has actually responded (see
  // ProviderDecision) — blank until then, even after status has moved to
  // "responded". Lets the client tell an accept from a decline instead of
  // both looking like the same generic "Responded" state.
  final String providerDecision;
  final String providerMessage;
  final DateTime? respondedAt;
  final DateTime firstUnlockedAt;
  final DateTime lastViewedAt;
}

/// Mirrors provider_search.models.ProviderMatch.DECISION_CHOICES.
class ProviderDecision {
  static const accepted = 'accepted';
  static const declined = 'declined';

  static String label(String decision) => switch (decision) {
        accepted => 'Accepted',
        declined => 'Declined',
        _ => decision,
      };
}

/// Mirrors provider_search.models.ProviderMatch.STATUS_CHOICES — minus
/// "searching"/"found" (those describe a provider search hasn't produced an
/// unlocked entry for yet, so a ProviderMatch row can never actually hold
/// them — see ProviderMatch's docstring) and "matched" (retired: rows are
/// no longer auto-created on search, so nothing is ever created in that
/// state anymore; still handled by [label]'s fallback if old data has it).
class ProviderMatchStatus {
  static const requested = 'requested';
  static const responded = 'responded';
  static const contacted = 'contacted';
  static const booked = 'booked';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
  static const archived = 'archived';

  static const all = [requested, responded, contacted, booked, inProgress, completed, cancelled, archived];

  static String label(String status) => switch (status) {
        requested => 'Requested',
        responded => 'Responded',
        contacted => 'Contacted',
        booked => 'Booked',
        inProgress => 'In Progress',
        completed => 'Completed',
        cancelled => 'Cancelled',
        archived => 'Archived',
        'matched' => 'Matched', // legacy rows only — never a fresh default
        _ => status,
      };
}
