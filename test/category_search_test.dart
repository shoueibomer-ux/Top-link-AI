import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/category_suggestions.dart';
import 'package:toplinkai_app/chat/chat_screen.dart';
import 'package:toplinkai_app/onboarding/category_detail_page.dart';
import 'package:toplinkai_app/onboarding/category_search.dart';
import 'package:toplinkai_app/home/home_screen.dart';
import 'package:toplinkai_app/onboarding/category_step.dart';
import 'package:toplinkai_app/onboarding/onboarding_screen.dart';
import 'package:toplinkai_app/onboarding/urgency_step.dart';
import 'package:toplinkai_app/widgets/category_search_view.dart';
import 'package:toplinkai_app/onboarding/service_category.dart';
import 'package:toplinkai_app/onboarding/service_list_page.dart';

ServiceCategory _category(String label, String slug) =>
    ServiceCategory(label: label, icon: Icons.build, whatWeCover: '', workerNoun: 'pros', slug: slug);

final _plumbing = _category('Plumbing', 'plumbing');
final _electrical = _category('Electrical', 'electrical');
final _hvac = _category('HVAC', 'hvac');
final _roofing = _category('Roofing', 'roofing');
final _kitchen = _category('Kitchen Renovation', 'kitchen-renovation');
final _all = [_plumbing, _electrical, _hvac, _roofing, _kitchen];

List<String> _labels(List<CategorySuggestion> suggestions) => [for (final s in suggestions) s.category.label];

void main() {
  group('normalizeSearchQuery', () {
    test('trims, lower-cases and collapses whitespace', () {
      expect(normalizeSearchQuery('  Leaking   PIPE '), 'leaking pipe');
      expect(normalizeSearchQuery('   '), '');
    });
  });

  group('buildCategorySuggestions: category names', () {
    test('a partial name matches: "plumb" -> Plumbing', () {
      final result = buildCategorySuggestions('plumb', _all, RemoteCategorySuggestions.none);
      expect(_labels(result), ['Plumbing']);
      expect(result.single.reason, SuggestionReason.name);
    });

    test('matching ignores case and surrounding space', () {
      expect(_labels(buildCategorySuggestions('  PLUMBING ', _all, RemoteCategorySuggestions.none)), ['Plumbing']);
    });

    test('a word inside a multi-word name matches, ranked after names that start with it', () {
      final categories = [_kitchen, _category('Renovation Planning', 'planning')];
      final result = buildCategorySuggestions('reno', categories, RemoteCategorySuggestions.none);
      // "Renovation Planning" starts with it; "Kitchen Renovation" only has it as a later word.
      expect(_labels(result), ['Renovation Planning', 'Kitchen Renovation']);
    });

    test('a query that is not part of any name matches nothing', () {
      expect(buildCategorySuggestions('zzzz', _all, RemoteCategorySuggestions.none), isEmpty);
    });

    test('an empty query offers nothing, not everything', () {
      expect(buildCategorySuggestions('', _all, RemoteCategorySuggestions.none), isEmpty);
      expect(buildCategorySuggestions('   ', _all, RemoteCategorySuggestions.none), isEmpty);
    });
  });

  group('buildCategorySuggestions: backend keyword results', () {
    test('free text resolves to the classifier\'s category: "leaking pipe" -> Plumbing', () {
      const remote = RemoteCategorySuggestions(categories: ['plumbing']);
      final result = buildCategorySuggestions('leaking pipe', _all, remote);
      expect(_labels(result), ['Plumbing']);
      expect(result.single.reason, SuggestionReason.description);
    });

    test('a partly typed keyword suggests its category, naming the keyword', () {
      const remote = RemoteCategorySuggestions(keywords: [KeywordSuggestion(keyword: 'faucet', category: 'plumbing')]);
      final result = buildCategorySuggestions('fauc', _all, remote);
      expect(_labels(result), ['Plumbing']);
      expect(result.single.reason, SuggestionReason.keyword);
      expect(result.single.keyword, 'faucet');
    });

    test('a category is listed once, under the strongest reason', () {
      const remote = RemoteCategorySuggestions(
        categories: ['plumbing'],
        keywords: [KeywordSuggestion(keyword: 'plumber', category: 'plumbing')],
      );
      final result = buildCategorySuggestions('plumb', _all, remote);
      expect(_labels(result), ['Plumbing']);
      expect(result.single.reason, SuggestionReason.name);
    });

    test('order: names, then whole-text matches, then keyword hits; the classifier\'s ranking is kept', () {
      const remote = RemoteCategorySuggestions(
        categories: ['roofing', 'plumbing'],
        keywords: [KeywordSuggestion(keyword: 'furnace', category: 'hvac')],
      );
      final result = buildCategorySuggestions('elec', _all, remote);
      expect(_labels(result), ['Electrical', 'Roofing', 'Plumbing', 'HVAC']);
    });

    test('slugs the app has no category for are skipped, not shown as dead ends', () {
      const remote = RemoteCategorySuggestions(
        categories: ['not-in-the-catalog', 'plumbing'],
        keywords: [KeywordSuggestion(keyword: 'x', category: 'also-missing')],
      );
      expect(_labels(buildCategorySuggestions('pipe', _all, remote)), ['Plumbing']);
    });

    test('with no backend answer, name matching alone still works', () {
      expect(buildCategorySuggestions('leaking pipe', _all, RemoteCategorySuggestions.none), isEmpty);
      expect(_labels(buildCategorySuggestions('roof', _all, RemoteCategorySuggestions.none)), ['Roofing']);
    });

    test('the list is capped', () {
      final many = [for (var i = 0; i < 20; i++) _category('Service $i', 's$i')];
      final remote = RemoteCategorySuggestions(categories: [for (final c in many) c.slug]);
      expect(buildCategorySuggestions('service', many, remote).length, maxCategorySuggestions);
    });
  });

  group('RemoteCategorySuggestions.fromJson', () {
    test('parses the endpoint\'s response', () {
      final parsed = RemoteCategorySuggestions.fromJson({
        'query': 'leak',
        'categories': ['plumbing', 'roofing'],
        'keywords': [
          {'keyword': 'leak', 'category': 'plumbing'},
        ],
      });
      expect(parsed.categories, ['plumbing', 'roofing']);
      expect(parsed.keywords.single.keyword, 'leak');
      expect(parsed.keywords.single.category, 'plumbing');
    });

    test('tolerates missing lists', () {
      final parsed = RemoteCategorySuggestions.fromJson({'query': 'x'});
      expect(parsed.categories, isEmpty);
      expect(parsed.keywords, isEmpty);
    });
  });

  group('CategorySearchView', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // The results read the flat category list.
      serviceCategories = List.of(_all);
      serviceCategoryGroups = [];
    });

    void useRealisticDeviceSize(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    /// Hosts the view with some scrolling content below it, recording what it selects.
    Future<List<ServiceCategory>> pumpStep(
      WidgetTester tester, {
      CategorySuggestionsFetcher? fetcher,
    }) async {
      useRealisticDeviceSize(tester);
      final selected = <ServiceCategory>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: CategorySearchView(
                onSelect: selected.add,
                suggestionsFetcher: fetcher ?? (_) async => RemoteCategorySuggestions.none,
                child: ListView(
                  key: const Key('content'),
                  children: [for (var i = 0; i < 30; i++) Text('content row $i')],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return selected;
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 350)); // past the typing pause
      await tester.pump(); // let the (fake) answer land
    }

    testWidgets('the search bar sits above the content', (tester) async {
      await pumpStep(tester);
      final bar = tester.getRect(find.byType(TextField));
      final content = tester.getRect(find.byKey(const Key('content')));
      expect(bar.bottom, lessThanOrEqualTo(content.top));
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('typing a partial category name suggests it, and hides the content', (tester) async {
      await pumpStep(tester);
      await type(tester, 'plumb');

      expect(find.text('Plumbing'), findsOneWidget);
      expect(find.text('Electrical'), findsNothing);
      expect(find.byKey(const Key('content')), findsNothing);
    });

    testWidgets('free text is resolved through the backend keyword classifier', (tester) async {
      String? asked;
      await pumpStep(
        tester,
        fetcher: (query) async {
          asked = query;
          return const RemoteCategorySuggestions(categories: ['plumbing']);
        },
      );
      await type(tester, 'Leaking Pipe');

      expect(asked, 'leaking pipe');
      expect(find.text('Plumbing'), findsOneWidget);
      expect(find.text('Matches "leaking pipe"'), findsOneWidget);
    });

    testWidgets('a keyword suggestion names the keyword', (tester) async {
      await pumpStep(
        tester,
        fetcher: (_) async => const RemoteCategorySuggestions(
          keywords: [KeywordSuggestion(keyword: 'furnace', category: 'hvac')],
        ),
      );
      await type(tester, 'furn');

      expect(find.text('HVAC'), findsOneWidget);
      expect(find.text('Keyword: furnace'), findsOneWidget);
    });

    testWidgets('a burst of keystrokes makes one backend request, for the final text', (tester) async {
      final asked = <String>[];
      await pumpStep(
        tester,
        fetcher: (query) async {
          asked.add(query);
          return RemoteCategorySuggestions.none;
        },
      );
      for (final text in ['pl', 'plu', 'plum']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 400));

      expect(asked, ['plum']);
    });

    testWidgets('a single character is not sent to the backend', (tester) async {
      final asked = <String>[];
      await pumpStep(
        tester,
        fetcher: (query) async {
          asked.add(query);
          return RemoteCategorySuggestions.none;
        },
      );
      await type(tester, 'p');
      expect(asked, isEmpty);
    });

    testWidgets('a slow, older answer does not overwrite a newer one', (tester) async {
      await pumpStep(
        tester,
        fetcher: (query) => Future.delayed(
          query == 'pipe' ? const Duration(seconds: 2) : const Duration(milliseconds: 10),
          () => query == 'pipe'
              ? const RemoteCategorySuggestions(categories: ['plumbing'])
              : const RemoteCategorySuggestions(categories: ['electrical']),
        ),
      );
      await tester.enterText(find.byType(TextField), 'pipe');
      await tester.pump(const Duration(milliseconds: 350)); // 'pipe' request now in flight (slow)
      await tester.enterText(find.byType(TextField), 'wiring');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50)); // 'wiring' answers
      await tester.pump(const Duration(seconds: 3)); // the stale 'pipe' answer finally arrives
      await tester.pump();

      expect(find.text('Electrical'), findsOneWidget);
      expect(find.text('Plumbing'), findsNothing);
    });

    testWidgets('selecting a suggestion opens that category\'s provider page directly', (tester) async {
      await pumpStep(tester);
      await type(tester, 'plumb');
      await tester.tap(find.text('Plumbing'));
      await tester.pumpAndSettle();

      expect(find.byType(CategoryDetailPage), findsOneWidget);
      expect(find.text('WHAT WE COVER'), findsOneWidget);
      expect(tester.widget<CategoryDetailPage>(find.byType(CategoryDetailPage)).category.slug, 'plumbing');
      // The shortcut skips the group / service lists entirely.
      expect(find.byType(ServiceListPage), findsNothing);
    });

    testWidgets('submitting the search opens the best match directly', (tester) async {
      await pumpStep(
        tester,
        fetcher: (_) async => const RemoteCategorySuggestions(categories: ['plumbing']),
      );
      await tester.enterText(find.byType(TextField), 'leaking pipe');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byType(CategoryDetailPage), findsOneWidget);
      expect(tester.widget<CategoryDetailPage>(find.byType(CategoryDetailPage)).category.slug, 'plumbing');
    });

    testWidgets('confirming on the detail page selects the category, like the grid route does', (tester) async {
      final selected = await pumpStep(tester);
      await type(tester, 'roof');
      await tester.tap(find.text('Roofing'));
      await tester.pumpAndSettle();
      expect(selected, isEmpty); // opening the page selects nothing yet

      await tester.tap(find.text('Select this category'));
      await tester.pumpAndSettle();

      expect(selected.map((c) => c.slug), ['roofing']);
    });

    testWidgets('backing out of the detail page selects nothing and keeps the search', (tester) async {
      final selected = await pumpStep(tester);
      await type(tester, 'roof');
      await tester.tap(find.text('Roofing'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(selected, isEmpty);
      expect(find.byType(CategoryDetailPage), findsNothing);
      expect(find.text('Roofing'), findsOneWidget); // still in the results
    });

    testWidgets('submitting with no match stays put and shows the empty state', (tester) async {
      await pumpStep(tester);
      await tester.enterText(find.byType(TextField), 'zzzz qqqq');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byType(CategoryDetailPage), findsNothing);
      expect(find.text('No categories match "zzzz qqqq"'), findsOneWidget);
    });

    testWidgets('no match: a clear empty state pointing at Ask AI', (tester) async {
      await pumpStep(tester);
      await type(tester, 'zzzz qqqq');

      expect(find.text('No categories match "zzzz qqqq"'), findsOneWidget);
      expect(find.textContaining('Ask AI'), findsWidgets);
      expect(find.widgetWithText(OutlinedButton, 'Ask AI'), findsOneWidget);
      expect(find.byKey(const Key('content')), findsNothing);
    });

    testWidgets('the empty state\'s Ask AI button opens the chat', (tester) async {
      await pumpStep(tester);
      await type(tester, 'zzzz qqqq');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Ask AI'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('no "no matches" flash while the backend is still answering', (tester) async {
      await pumpStep(
        tester,
        fetcher: (_) => Future.delayed(
          const Duration(seconds: 2),
          () => const RemoteCategorySuggestions(categories: ['plumbing']),
        ),
      );
      await tester.enterText(find.byType(TextField), 'leaking pipe');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('No categories match'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Plumbing'), findsOneWidget);
    });

    testWidgets('when the backend is unreachable, name matches still work', (tester) async {
      await pumpStep(tester, fetcher: (_) async => throw Exception('offline'));
      await type(tester, 'plumb');

      expect(find.text('Plumbing'), findsOneWidget);
    });

    testWidgets('when the backend is unreachable and nothing matches, the empty state says so', (tester) async {
      await pumpStep(tester, fetcher: (_) async => throw Exception('offline'));
      await type(tester, 'leaking pipe');

      expect(find.text('No categories match "leaking pipe"'), findsOneWidget);
      expect(find.textContaining('unavailable'), findsOneWidget);
    });

    testWidgets('the clear button empties the search and brings the content back', (tester) async {
      await pumpStep(tester);
      await type(tester, 'plumb');
      expect(find.byKey(const Key('content')), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      expect(find.byKey(const Key('content')), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsNothing);
    });
  });

  group('Home screen search bar', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      serviceCategories = List.of(_all);
      serviceCategoryGroups = [];
    });

    void useRealisticDeviceSize(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> pumpHome(WidgetTester tester) async {
      useRealisticDeviceSize(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(category: _plumbing, urgency: Urgency.today),
        ),
      );
      await tester.pump();
    }

    testWidgets('the search bar is directly below the app header', (tester) async {
      await pumpHome(tester);

      final header = tester.getRect(find.byType(AppBar));
      final field = tester.getRect(find.byType(TextField));
      expect(field.top, greaterThanOrEqualTo(header.bottom));
      expect(field.top - header.bottom, lessThan(32)); // nothing between them
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('the field is empty and shows no hint text until the user types', (tester) async {
      await pumpHome(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      expect(field.decoration!.hintText, isNull);
      expect(find.textContaining('plumber'), findsNothing);
      expect(find.textContaining('leaking pipe'), findsNothing);
      // Just the icon inside the field.
      expect(find.descendant(of: find.byType(TextField), matching: find.byType(Text)), findsNothing);
    });

    // NOTE: there used to be a dedicated "the search bar stays put while Home
    // content scrolls underneath" test here, exercised against a long fake
    // provider list. Home's content is fixed and short now (no provider list
    // in this phase — see docs/ai-agent-system.md's Phase 0), so it no longer
    // scrolls far enough to exercise that meaningfully; the bar sitting
    // outside the scrolling area is still covered structurally by 'it belongs
    // to the Home tab only' and the field-position test above.

    testWidgets('typing replaces the Home content with results; clearing restores it', (tester) async {
      await pumpHome(tester);
      expect(find.text("You're all set!"), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'plumb');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Plumbing'), findsOneWidget);
      expect(find.text("You're all set!"), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text("You're all set!"), findsOneWidget);
    });

    testWidgets('it belongs to the Home tab only', (tester) async {
      await pumpHome(tester);
      expect(find.byType(CategorySearchView), findsOneWidget);

      // (Profile is left out on purpose: the search bar is only ever built for the
      // Home tab, and that tab's own layout has nothing to do with this check.)
      for (final tab in ['History', 'Ask AI']) {
        await tester.tap(find.text(tab));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(CategorySearchView), findsNothing, reason: 'search bar leaked onto $tab');
      }

      await tester.tap(find.text('Home'));
      await tester.pump();
      expect(find.byType(CategorySearchView), findsOneWidget);
    });

    testWidgets('the onboarding category step no longer has a search bar', (tester) async {
      useRealisticDeviceSize(tester);
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
      await tester.pump();

      expect(find.text('What do you need help with?'), findsOneWidget);
      expect(find.byType(CategorySearchView), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a suggestion opens the category page directly, and confirming starts a request in it',
        (tester) async {
      await pumpHome(tester);
      await tester.enterText(find.byType(TextField), 'plumb');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.tap(find.text('Plumbing'));
      await tester.pumpAndSettle();

      expect(find.byType(CategoryDetailPage), findsOneWidget);
      expect(find.byType(ServiceListPage), findsNothing);

      await tester.tap(find.text('Select this category'));
      await tester.pumpAndSettle();

      // Onboarding, already past the category step, with the category chosen.
      final onboarding = tester.widget<OnboardingScreen>(find.byType(OnboardingScreen));
      expect(onboarding.initialCategory?.slug, 'plumbing');
      expect(find.byType(UrgencyStep), findsOneWidget);
      expect(find.byType(CategoryStep), findsNothing);
    });

    testWidgets('backing out of the category page leaves Home as it was', (tester) async {
      await pumpHome(tester);
      await tester.enterText(find.byType(TextField), 'plumb');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.tap(find.text('Plumbing'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });
  });

  group('OnboardingScreen with an initial category', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('starts at the urgency step, and without one it starts at the category step', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(home: OnboardingScreen(key: const Key('with'), initialCategory: _plumbing)));
      await tester.pump();
      expect(find.byType(UrgencyStep), findsOneWidget);
      expect(find.byType(CategoryStep), findsNothing);

      // A different key, so the first screen's state isn't reused.
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen(key: Key('without'))));
      await tester.pump();
      expect(find.byType(CategoryStep), findsOneWidget);
    });
  });
}
