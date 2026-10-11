import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toplinkai_app/app_colors.dart';
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
    Future<void> pumpLogo(WidgetTester tester, Widget logo, {double width = 1080, Color? background}) async {
      useTallPhone(tester, width: width);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(backgroundColor: background, body: Center(child: logo)),
      ));
      await tester.pump(const Duration(seconds: 1));
    }

    List<InlineSpan> wordmarkSpans(WidgetTester tester) =>
        (tester.widget<Text>(find.byKey(const Key('wordmark'))).textSpan! as TextSpan).children!;

    for (final width in [400.0, 1080.0, 1600.0]) {
      testWidgets('shows the tm mark and the lowercase "tabmatch" wordmark at ${width.toInt()}px wide',
          (tester) async {
        await pumpLogo(tester, const AppLogo(), width: width);

        final assetNames = tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => (image.image as AssetImage).assetName)
            .toList();
        expect(assetNames, ['assets/brand/tabmatch_icon_192.png']);
        expect(tester.widget<Text>(find.byKey(const Key('wordmark'))).textSpan!.toPlainText(), 'tabmatch');
        expect(find.textContaining('Top-Link'), findsNothing);
        expect(find.textContaining('TLA'), findsNothing);
      });
    }

    testWidgets('on a dark background "tab" is white and "match" is turquoise', (tester) async {
      await pumpLogo(tester, const AppLogo(), background: AppColors.navy);
      final spans = wordmarkSpans(tester).cast<TextSpan>();
      expect([for (final s in spans) s.text], ['tab', 'match']);
      expect(spans[0].style!.color, AppColors.white);
      expect(spans[1].style!.color, const Color(0xFF19C3B1));
    });

    testWidgets('on a light background "tab" is navy (#0B1F3A)', (tester) async {
      await pumpLogo(tester, const AppLogo(onLight: true));
      final spans = wordmarkSpans(tester).cast<TextSpan>();
      expect(spans[0].style!.color, const Color(0xFF0B1F3A));
      expect(spans[1].style!.color, const Color(0xFF19C3B1));
    });

    testWidgets('the wordmark shrinks to fit instead of overflowing in a narrow space', (tester) async {
      useTallPhone(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 150, child: AppLogo(height: 40)))),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('wordmark')), findsOneWidget);
    });

    testWidgets('the mark can be shown alone', (tester) async {
      await pumpLogo(tester, const AppLogo(showWordmark: false));
      expect(find.byType(Image), findsOneWidget);
      expect(find.byKey(const Key('wordmark')), findsNothing);
    });

    testWidgets('is announced as Tabmatch', (tester) async {
      await pumpLogo(tester, const AppLogo());
      expect(find.bySemanticsLabel('Tabmatch'), findsWidgets);
    });
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
