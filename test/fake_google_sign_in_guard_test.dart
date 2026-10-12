import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toplinkai_app/api/api_config.dart';
import 'package:toplinkai_app/provider/google_sign_in_service.dart';

// The fake Google sign-in is a developer shortcut: it must work only in a debug
// build, against a local dev server, and never in anything that ships.
void main() {
  group('when the fake sign-in is on', () {
    test('only a debug build that was given an email can use it', () {
      expect(fakeGoogleSignInEnabled(isDebug: true, fakeEmail: 'dev@example.com'), isTrue);
      expect(fakeGoogleSignInEnabled(isDebug: true, fakeEmail: ''), isFalse);
    });

    test('a release or profile build (not debug) can never use it, even if given an email', () {
      expect(fakeGoogleSignInEnabled(isDebug: false, fakeEmail: 'dev@example.com'), isFalse);
      expect(fakeGoogleSignInEnabled(isDebug: false, fakeEmail: ''), isFalse);
    });

    test('this test run was not given the define, so the real service is not faking', () {
      expect(GoogleSignInService.usesFakeSignIn, isFalse);
    });
  });

  group('a release build given the fake email', () {
    test('refuses to start', () {
      expect(
        () => checkFakeGoogleSignIn(fakeEmail: 'dev@example.com', isRelease: true),
        throwsA(isA<ApiConfigException>().having((e) => e.message, 'message', contains('DEV_FAKE_GOOGLE_EMAIL'))),
      );
    });

    test('is fine without it, and a debug build may have it', () {
      expect(() => checkFakeGoogleSignIn(fakeEmail: '', isRelease: true), returnsNormally);
      expect(() => checkFakeGoogleSignIn(fakeEmail: '   ', isRelease: true), returnsNormally);
      expect(() => checkFakeGoogleSignIn(fakeEmail: 'dev@example.com', isRelease: false), returnsNormally);
    });
  });

  group('the files that configure real builds never turn it on', () {
    test('the defines template and the README release commands do not mention it', () {
      expect(File('dart_defines.example.json').readAsStringSync(), isNot(contains('DEV_FAKE')));
      final readme = File('README.md').readAsStringSync();
      // Splitting on the code fence leaves the fenced blocks at the odd positions.
      final chunks = readme.split('```');
      for (var i = 1; i < chunks.length; i += 2) {
        if (chunks[i].contains('--release')) {
          expect(chunks[i], isNot(contains('DEV_FAKE_GOOGLE_EMAIL')), reason: chunks[i]);
        }
      }
    });
  });
}
