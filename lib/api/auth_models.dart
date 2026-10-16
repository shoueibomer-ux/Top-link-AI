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

/// The answer to POST /api/accounts/google/: a client signing in with Google.
class ClientSignIn {
  const ClientSignIn({
    required this.tokens,
    required this.email,
    required this.fullName,
    required this.isNewAccount,
  });

  factory ClientSignIn.fromJson(Map<String, dynamic> json) {
    return ClientSignIn(
      tokens: AuthTokens.fromJson(json),
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      isNewAccount: json['is_new_account'] as bool? ?? false,
    );
  }

  final AuthTokens tokens;
  final String email;
  final String fullName;
  final bool isNewAccount;
}
