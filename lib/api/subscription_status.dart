class SubscriptionStatus {
  const SubscriptionStatus({
    required this.status,
    this.startDate,
    this.expiryDate,
    this.unlockCredits = 0,
    this.hasAccess,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      status: json['status'] as String,
      startDate: json['start_date'] != null ? DateTime.parse(json['start_date'] as String) : null,
      expiryDate: json['expiry_date'] != null ? DateTime.parse(json['expiry_date'] as String) : null,
      unlockCredits: json['unlock_credits'] as int? ?? 0,
      hasAccess: json['has_access'] as bool?,
    );
  }

  final String status; // 'active' | 'trial' | 'inactive'
  final DateTime? startDate;
  final DateTime? expiryDate;

  /// Unspent one-time unlocks (the paywall's "$4.99 one-time" option) — each
  /// is spent silently by the next provider this device unlocks. See
  /// matching.models.UnlockCredit.
  final int unlockCredits;

  /// The backend's verdict on whether the up-front gate should let this
  /// device in (an active subscription OR having ever bought a one-time
  /// unlock — see matching.access.has_access). Null when talking to a
  /// backend that predates the field, in which case [isActive] decides.
  final bool? hasAccess;

  bool get isActive {
    final statusGrantsAccess = status == 'active' || status == 'trial';
    final notExpired = expiryDate == null || expiryDate!.isAfter(DateTime.now());
    return statusGrantsAccess && notExpired;
  }

  /// What AppEntryPoint should use instead of [isActive]: a one-time buyer
  /// isn't a subscriber, but must not be bounced back to the paywall.
  bool get canEnterApp => hasAccess ?? isActive;
}
