/// SimpleJWT's standard {access, refresh} pair, as returned by the provider
/// sign-in (and, mixed into that response, by the token refresh).
class AuthTokens {
  const AuthTokens({required this.access, required this.refresh});

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      access: json['access'] as String,
      refresh: json['refresh'] as String,
    );
  }

  final String access;
  final String refresh;
}

/// Mirrors accounts.models.UserRole.
class UserRole {
  static const customer = 'customer';
  static const provider = 'provider';
  static const admin = 'admin';
}

/// From GET /api/accounts/me/ (accounts.serializers.UserProfileSerializer).
class AccountProfile {
  const AccountProfile({
    required this.email,
    required this.role,
    required this.fullName,
  });

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    return AccountProfile(
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? UserRole.customer,
      fullName: json['full_name'] as String? ?? '',
    );
  }

  final String email;
  final String role;
  final String fullName;
}
