import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:toplinkai_app/provider/google_sign_in_service.dart';

void main() {
  group('Google sign-in failure messages', () {
    test('every failure code gets a plain-language message, never the raw code', () {
      for (final code in GoogleSignInExceptionCode.values) {
        final message = googleSignInFailureMessage(code);
        expect(message, isNotEmpty, reason: code.name);
        expect(message.toLowerCase(), isNot(contains(code.name.toLowerCase())), reason: code.name);
        expect(message, isNot(contains('Exception')), reason: code.name);
      }
    });

    test('the unknown error (no Google account on the device) says what to do', () {
      final message = googleSignInFailureMessage(GoogleSignInExceptionCode.unknownError);
      expect(message, contains('Google account'));
      expect(message, contains('Passwords & accounts'));
    });

    test('a misconfigured build and an old Play services are told apart', () {
      expect(googleSignInFailureMessage(GoogleSignInExceptionCode.clientConfigurationError), contains('connect@tabmatch.ca'));
      expect(googleSignInFailureMessage(GoogleSignInExceptionCode.providerConfigurationError), contains('Google Play services'));
    });
  });
}
