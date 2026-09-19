import 'real_provider.dart';

/// Response from POST /api/chat/refine/ (provider_search.views.ChatRefineView) —
/// the free-text alternative to tapping a fixed category during onboarding.
class ChatRefineResult {
  const ChatRefineResult({
    required this.category,
    required this.urgency,
    required this.notes,
    required this.subscriptionRequired,
    required this.providers,
  });

  factory ChatRefineResult.fromJson(Map<String, dynamic> json) {
    final providers = (json['providers'] as List<dynamic>)
        .map((p) => RealProvider.fromJson(p as Map<String, dynamic>))
        .toList();
    return ChatRefineResult(
      category: json['category'] as String?,
      urgency: json['urgency'] as String? ?? 'exploring',
      notes: json['notes'] as String? ?? '',
      subscriptionRequired: json['subscription_required'] as bool? ?? false,
      providers: providers,
    );
  }

  // Null means neither the AI call nor keyword matching could identify a
  // supported category — the UI should ask the client to rephrase.
  final String? category;
  final String urgency;
  final String notes;
  final bool subscriptionRequired;
  final List<RealProvider> providers;
}
