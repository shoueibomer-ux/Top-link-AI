import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toplinkai_app/pages/about_us_page.dart';
import 'package:toplinkai_app/widgets/app_logo.dart';

void useTallPhone(WidgetTester tester, {double width = 1080}) {
  tester.view.physicalSize = Size(width, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('AppLogo', () {
    Future<void> pumpLogo(WidgetTester tester, {required double width}) async {
      useTallPhone(tester, width: width);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: AppLogo()))));
      // Well past the old ~700ms "peek" timer, which used to reveal a
      // wordmark beside the circle.
      await tester.pump(const Duration(seconds: 3));
    }

    for (final width in [400.0, 1080.0, 1600.0]) {
      testWidgets('shows only the TLA roundel — no wordmark or tagline text — at ${width.toInt()}px wide',
          (tester) async {
        await pumpLogo(tester, width: width);

        final assetNames = tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => (image.image as AssetImage).assetName)
            .toList();
        expect(assetNames, ['assets/images/toplinkai_icon.png']);
        expect(find.textContaining('AI-Powered'), findsNothing);
        expect(find.textContaining('Top-Link'), findsNothing);
        expect(find.textContaining('TOP LINK'), findsNothing);
      });
    }
  });

  group('AboutUsPage', () {
    testWidgets('shows the new tagline, both audience sections, the 3 steps, categories, and footer note',
        (tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(const MaterialApp(home: AboutUsPage()));

      expect(find.text('Connecting Edmonton homeowners with trusted local service providers, faster.'),
          findsOneWidget);

      for (final heading in ['For Customers', 'For Providers', 'How It Works', 'Popular categories']) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }

      for (final point in [...AboutUsPage.customerPoints, ...AboutUsPage.providerPoints]) {
        expect(find.text(point), findsOneWidget, reason: point);
      }
      expect(find.text('Free to join, no commitment required'), findsOneWidget);
      expect(find.text('No more endless searching or cold calls'), findsOneWidget);

      expect(find.text('Tell us what you need'), findsOneWidget);
      expect(find.text('Get matched instantly'), findsOneWidget);
      expect(find.text('Connect and get it done'), findsOneWidget);
      for (final n in ['1', '2', '3']) {
        expect(find.text(n), findsOneWidget);
      }

      for (final category in ['Electrical', 'Plumbing', 'HVAC', 'Cleaning', 'Contractors', 'Automotive', 'Landscaping', 'Moving', 'Events']) {
        expect(find.text(category), findsOneWidget, reason: category);
      }
      expect(find.text('and more'), findsOneWidget);

      expect(find.text('Launching in Edmonton — expanding to Calgary, Fort McMurray, and Red Deer soon.'),
          findsOneWidget);
    });

    testWidgets('no longer shows the old single-paragraph copy', (tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(const MaterialApp(home: AboutUsPage()));
      expect(find.textContaining('We started in Edmonton, Alberta'), findsNothing);
    });

    testWidgets('does not overflow on a narrow phone', (tester) async {
      useTallPhone(tester, width: 360);
      await tester.pumpWidget(const MaterialApp(home: AboutUsPage()));
      expect(tester.takeException(), isNull);
    });
  });
}
