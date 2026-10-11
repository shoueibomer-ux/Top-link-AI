import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/main.dart';
import 'package:toplinkai_app/role/role_choice_screen.dart';
import 'package:toplinkai_app/widgets/app_drawer.dart';

// The app is Tabmatch. Each test names what it protects: the visible name, the
// brand assets, and the identifiers that are deliberately NOT renamed yet.

String read(String path) => File(path).readAsStringSync();

({int width, int height}) pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  return (width: data.getUint32(16), height: data.getUint32(20));
}

void main() {
  group('the visible name', () {
    test('no Dart source in lib/ still says Top-Link (any spelling)', () {
      final pattern = RegExp(r'top[ -]?link|toplink', caseSensitive: false);
      final offenders = [
        for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
          if (file.path.endsWith('.dart') && pattern.hasMatch(file.readAsStringSync())) file.path,
      ];
      expect(offenders, isEmpty);
    });

    test('Android and iOS call the app Tabmatch', () {
      expect(read('android/app/src/main/AndroidManifest.xml'), contains('android:label="Tabmatch"'));
      final plist = read('ios/Runner/Info.plist');
      expect(RegExp(r'<key>CFBundleDisplayName</key>\s*<string>Tabmatch</string>').hasMatch(plist), isTrue);
      expect(RegExp(r'<key>CFBundleName</key>\s*<string>Tabmatch</string>').hasMatch(plist), isTrue);
      expect(plist, contains('Tabmatch uses your location'));
      expect(read('web/index.html'), contains('<title>Tabmatch</title>'));
      expect(read('web/manifest.json'), contains('"name": "Tabmatch"'));
    });

    testWidgets('the app title is Tabmatch', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const TabmatchApp());
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, 'Tabmatch');
    });

    testWidgets('the role screen welcomes you to Tabmatch with the logo on a light background', (tester) async {
      await tester.pumpWidget(MaterialApp(home: RoleChoiceScreen(onChosen: (_) {})));
      expect(find.text('Welcome to Tabmatch'), findsOneWidget);
      expect(find.byKey(const Key('wordmark')), findsOneWidget);
    });

    testWidgets('the drawer header shows the Tabmatch logo', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(drawer: AppDrawer())));
      final scaffold = tester.firstState<ScaffoldState>(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wordmark')), findsOneWidget);
      expect(find.textContaining('Top-Link'), findsNothing);
    });
  });

  group('the brand assets', () {
    test('the icon sizes exist at the right dimensions', () {
      for (final size in [1024, 512, 192, 180, 48]) {
        final dims = pngSize('assets/brand/tabmatch_icon_$size.png');
        expect((dims.width, dims.height), (size, size), reason: '$size');
      }
      expect(pngSize('assets/brand/tabmatch_favicon_32.png').width, 32);
      expect(pngSize('assets/brand/tabmatch_icon_foreground_1024.png').width, 1024);
      expect(pngSize('assets/brand/tabmatch_icon_ios_1024.png').width, 1024);
    });

    test('the SVGs are the supplied icon, with and without the navy tile', () {
      final full = read('assets/brand/tabmatch_icon.svg');
      expect(full, contains('<rect width="1024" height="1024" rx="230" fill="#0B1F3A"/>'));
      final foreground = read('assets/brand/tabmatch_icon_foreground.svg');
      expect(foreground, isNot(contains('<rect')));
      for (final svg in [full, foreground]) {
        expect(svg, contains('points="506,442 621,570 832,294 832,717"'));
        expect(svg, contains('stroke="#19C3B1"'));
        expect(svg, contains('viewBox="0 0 1024 1024"'));
      }
    });

    test('the launcher icons are generated onto the navy background', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, contains('adaptive_icon_background: "#0B1F3A"'));
      expect(pubspec, contains('adaptive_icon_foreground: assets/brand/tabmatch_icon_foreground_1024.png'));
      expect(read('android/app/src/main/res/values/colors.xml'), contains('#0B1F3A'));
      expect(File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml').existsSync(), isTrue);
    });

    test('the splash is navy', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, contains('color: "#0B1F3A"'));
      expect(File('android/app/src/main/res/drawable/launch_background.xml').readAsStringSync(), contains('@drawable/splash'));
    });
  });

  group('identifiers that are deliberately not renamed', () {
    test('the package / bundle id stays com.toplinkai.app', () {
      expect(read('android/app/build.gradle.kts'), contains('applicationId = "com.toplinkai.app"'));
      expect(read('android/app/build.gradle.kts'), contains('namespace = "com.toplinkai.app"'));
      expect(File('android/app/src/main/kotlin/com/toplinkai/app/MainActivity.kt').existsSync(), isTrue);
      expect(read('ios/Runner.xcodeproj/project.pbxproj'), contains('PRODUCT_BUNDLE_IDENTIFIER = com.toplinkai.app;'));
      expect(read('macos/Runner/Configs/AppInfo.xcconfig'), contains('PRODUCT_BUNDLE_IDENTIFIER = com.toplinkai.app'));
    });

    test('the Dart package, the Render services and the database keep their names', () {
      expect(read('pubspec.yaml'), startsWith('name: toplinkai_app'));
      final render = read('render.yaml');
      for (final name in ['toplinkai-backend', 'toplinkai-db', 'toplinkai-redis', 'toplinkai-lead-jobs']) {
        expect(render, contains(name), reason: name);
      }
      expect(render, contains('databaseName: toplinkai'));
    });
  });
}
