class SubscriptionStatus {
  const SubscriptionStatus({required this.status, this.startDate, this.expiryDate});

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      status: json['status'] as String,
      startDate: json['start_date'] != null ? DateTime.parse(json['start_date'] as String) : null,
      expiryDate: json['expiry_date'] != null ? DateTime.parse(json['expiry_date'] as String) : null,
    );
  }

  final String status; // 'active' | 'trial' | 'inactive'
  final DateTime? startDate;
  final DateTime? expiryDate;

  bool get isActive {
    final statusGrantsAccess = status == 'active' || status == 'trial';
    final notExpired = expiryDate == null || expiryDate!.isAfter(DateTime.now());
    return statusGrantsAccess && notExpired;
  }
}
