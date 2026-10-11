import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The person closed the Google sign-in sheet; not an error worth showing.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

/// Sign-in can't work in this build or on this device; [message] says why.
class SignInUnavailable implements Exception {
  const SignInUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Gets a Google ID token for the backend to verify.
///
/// Real sign-in needs `--dart-define=GOOGLE_SERVER_CLIENT_ID=<the Web OAuth
/// client ID>` (the same ID the server lists in GOOGLE_OAUTH_CLIENT_IDS) and an
/// Android OAuth client for this package and signing key in Google Cloud.
///
/// For local development there's a stand-in: in a debug build,
/// `--dart-define=DEV_FAKE_GOOGLE_EMAIL=someone@example.com` skips Google and
/// sends "dev-fake:someone@example.com", which only a dev server started with
/// GOOGLE_DEV_FAKE_AUTH=True accepts. Release builds ignore it.
class GoogleSignInService {
  static const _fakeEmail = String.fromEnvironment('DEV_FAKE_GOOGLE_EMAIL');
  static const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get usesFakeSignIn => kDebugMode && _fakeEmail.isNotEmpty;

  static bool _initialized = false;

  static Future<String> getIdToken() async {
    if (usesFakeSignIn) return 'dev-fake:$_fakeEmail';
    if (_serverClientId.isEmpty) {
      throw const SignInUnavailable(
        'Google sign-in is not set up in this build (missing GOOGLE_SERVER_CLIENT_ID).',
      );
    }
    final google = GoogleSignIn.instance;
    if (!_initialized) {
      await google.initialize(serverClientId: _serverClientId);
      _initialized = true;
    }
    try {
      final account = await google.authenticate();
      final token = account.authentication.idToken;
      if (token == null) throw const SignInUnavailable('Google did not return a sign-in token. Try again.');
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) {
        throw const SignInCancelled();
      }
      throw SignInUnavailable('Google sign-in failed (${e.code.name}). Try again.');
    }
  }

  static Future<void> signOut() async {
    if (usesFakeSignIn || _serverClientId.isEmpty || !_initialized) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Signing out of the app matters more than telling Google.
    }
  }
}
