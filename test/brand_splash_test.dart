import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/app_colors.dart';
import 'package:toplinkai_app/provider/provider_gate.dart';
import 'package:toplinkai_app/role/role_choice_screen.dart';
import 'package:toplinkai_app/role/root_gate.dart';
import 'package:toplinkai_app/widgets/brand_splash.dart';

// On launch the app shows the TM logo alone, centered on navy, with a gentle
// pulse: no "Tabmatch" text under it, and the same picture as the native launch
// screen so nothing jumps when one hands over to the other.

String read(String path) => File(path).readAsStringSync();

Opacity pulsingOpacity(WidgetTester tester) => tester.widget<Opacity>(
  find.descendant(
    of: find.byKey(const Key('brand-splash')),
    matching: find.byType(Opacity),
  ),
);

void main() {
  group('the splash screen', () {
    testWidgets('is just the logo, centered, on the brand navy', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: BrandSplash()));

      final scaffold = tester.widget<Scaffold>(
        find.byKey(const Key('brand-splash')),
      );
      expect(scaffold.backgroundColor, AppColors.navy);
      expect(AppColors.navy, const Color(0xFF0B1F3A));

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        'assets/brand/tabmatch_splash_1152.png',
      );
      expect(
        tester.getSize(find.byType(Image)),
        const Size(288, 288),
      ); // the native splash draws it at 288 dp
      expect(
        tester.getCenter(find.byType(Image)),
        tester.getCenter(find.byKey(const Key('brand-splash'))),
      );

      expect(find.byType(Text), findsNothing); // no "Tabmatch" under the logo
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      'uses light status bar icons, like the native screen, so they do not flip at the hand-over',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: BrandSplash()));
        final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
        );
        expect(region.value.statusBarIconBrightness, Brightness.light);
        expect(region.value.statusBarColor, Colors.transparent);
      },
    );

    testWidgets(
      'the role screen that follows it sets dark icons for its light background',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: RoleChoiceScreen(onChosen: (_) {})),
        );
        final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
        );
        expect(region.value.statusBarIconBrightness, Brightness.dark);
      },
    );

    testWidgets(
      'starts fully visible, like the native screen, pulses softer and back once, then rests',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: BrandSplash()));
        expect(pulsingOpacity(tester).opacity, 1.0);
        final logoTransform = find
            .ancestor(of: find.byType(Image), matching: find.byType(Transform))
            .first;
        expect(
          tester.widget<Transform>(logoTransform).transform.getMaxScaleOnAxis(),
          closeTo(1.0, 1e-9),
        );

        await tester.pump(BrandSplash.pulseDuration ~/ 2);
        expect(
          pulsingOpacity(tester).opacity,
          closeTo(BrandSplash.softestOpacity, 0.01),
        );

        await tester.pump(BrandSplash.pulseDuration ~/ 2);
        expect(
          pulsingOpacity(tester).opacity,
          closeTo(1.0, 0.01),
        ); // back to full strength after the one pulse

        // It does not loop: after that frame nothing is animating, and it stays at full strength.
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.hasRunningAnimations, isFalse);
        await tester.pump(const Duration(seconds: 3));
        expect(pulsingOpacity(tester).opacity, 1.0);
      },
    );

    test('the animation lasts about a second at most', () {
      expect(
        BrandSplash.pulseDuration,
        lessThanOrEqualTo(const Duration(seconds: 1)),
      );
    });

    testWidgets(
      'settles by itself, so it never keeps the app busy while loading',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: BrandSplash()));
        await tester.pumpAndSettle(); // would time out if it kept animating
        expect(find.byType(Image), findsOneWidget);
      },
    );

    test(
      'the pulse stays gentle: never dimmer than 60% or smaller than 96%',
      () {
        var lowestOpacity = 1.0;
        var smallest = 1.0;
        for (var i = 0; i <= 100; i++) {
          final (opacity, scale) = BrandSplash.pulseAt(i / 100);
          lowestOpacity = lowestOpacity < opacity ? lowestOpacity : opacity;
          smallest = smallest < scale ? smallest : scale;
          expect(opacity, inInclusiveRange(0.6, 1.0));
          expect(scale, inInclusiveRange(0.96, 1.0));
        }
        expect(lowestOpacity, closeTo(0.6, 0.001));
        expect(smallest, closeTo(0.96, 0.001));
        expect(BrandSplash.pulseAt(0), (1.0, 1.0));
        expect(BrandSplash.pulseAt(1).$1, closeTo(1.0, 1e-9));
      },
    );

    testWidgets('stays still when the system asks for no animations', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(home: BrandSplash()),
        ),
      );
      await tester.pumpAndSettle(); // would never settle if it were pulsing
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('where it is used', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    testWidgets('the app opens on it while the saved role is read', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: RootGate()));
      expect(find.byType(BrandSplash), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(BrandSplash), findsNothing); // then the role screen
      expect(find.text('Welcome to Tabmatch'), findsOneWidget);
    });

    testWidgets(
      'a returning provider sees it, not a spinner, while their profile loads',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProviderGate()));
        expect(find.byType(BrandSplash), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });

  group('the native launch screens', () {
    test('no branding (wordmark) image is configured, on any platform', () {
      final pubspec = read('pubspec.yaml');
      final splash = pubspec
          .substring(pubspec.indexOf('flutter_native_splash:'))
          .split('flutter_launcher_icons:')
          .first;
      expect(
        RegExp(r'^\s*branding(_mode)?:', multiLine: true).hasMatch(splash),
        isFalse,
      );
      expect(pubspec, contains('color: "#0B1F3A"'));
      expect(pubspec, contains('image: assets/brand/tabmatch_splash_1152.png'));
    });

    test('Android draws only the logo on navy: no branding drawable is referenced or shipped', () {
      for (final path in [
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ]) {
        final xml = read(path);
        expect(xml, contains('@drawable/splash'));
        expect(xml, isNot(contains('branding')), reason: path);
      }
      for (final path in [
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ]) {
        final xml = read(path);
        expect(xml, contains('windowSplashScreenAnimatedIcon'));
        expect(xml, contains('#0B1F3A'));
        expect(xml, isNot(contains('BrandingImage')), reason: path);
      }
      final shipped = Directory('android/app/src/main/res')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('branding'))
          .toList();
      expect(shipped, isEmpty);
    });

    test('the Flutter splash is the same picture, size and color the native one is generated from', () {
      final png = File('assets/brand/tabmatch_splash_1152.png')
          .readAsBytesSync();
      final width =
          (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19];
      expect(width, 1152);
      expect(
        read('pubspec.yaml'),
        contains('- assets/brand/tabmatch_splash_1152.png'),
      ); // bundled for the Flutter side
      expect(BrandSplash.markAsset, 'assets/brand/tabmatch_splash_1152.png');
    });
  });
}
