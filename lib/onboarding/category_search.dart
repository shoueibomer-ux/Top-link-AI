import '../api/category_suggestions.dart';
import 'service_category.dart';

/// Why a category is being suggested for what the user typed.
enum SuggestionReason {
  /// The text matches the category's own name ("plumb" -> Plumbing).
  name,

  /// The text as a whole reads like this category, per the backend's keyword
  /// classifier ("leaking pipe" -> Plumbing).
  description,

  /// The text is the start of a keyword mapped to this category ("fauc" ->
  /// "faucet" -> Plumbing).
  keyword,
}

class CategorySuggestion {
  const CategorySuggestion({required this.category, required this.reason, this.keyword});

  final ServiceCategory category;
  final SuggestionReason reason;

  /// The matched keyword, for [SuggestionReason.keyword].
  final String? keyword;
}

/// The most suggestions shown at once — a search box, not a directory.
const maxCategorySuggestions = 6;

/// Lower-cases, trims and collapses runs of whitespace, so "  Leaking   PIPE "
/// and "leaking pipe" are the same query.
String normalizeSearchQuery(String query) => query.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

/// 0 = the label starts with [query], 1 = a word in it does, 2 = it merely
/// contains it, null = no match.
int? _nameRank(String label, String query) {
  final lower = label.toLowerCase();
  if (lower.startsWith(query)) return 0;
  if (lower.split(RegExp(r'[^a-z0-9]+')).any((word) => word.startsWith(query))) return 1;
  if (lower.contains(query)) return 2;
  return null;
}

/// Turns what the user typed into an ordered list of categories to offer.
///
/// Three sources, in this order (a category appears once, under the first
/// source that produced it):
///  1. category names that match the text — done here, on the client, so it
///     works instantly and offline;
///  2. the categories [remote] says the whole text describes — the backend's
///     keyword classifier, the same one Ask AI falls back to, so it isn't
///     re-implemented here;
///  3. categories whose keywords the text is the start of.
///
/// [remote] slugs that [categories] doesn't contain (the app's catalog and the
/// backend taxonomy can drift) are skipped rather than shown as dead ends.
/// Pass [RemoteCategorySuggestions.none] when the backend hasn't answered.
List<CategorySuggestion> buildCategorySuggestions(
  String query,
  List<ServiceCategory> categories,
  RemoteCategorySuggestions remote,
) {
  final text = normalizeSearchQuery(query);
  if (text.isEmpty) return const [];

  final bySlug = {for (final category in categories) category.slug: category};
  final seen = <String>{};
  final result = <CategorySuggestion>[];

  void add(ServiceCategory? category, SuggestionReason reason, [String? keyword]) {
    if (category == null || !seen.add(category.slug)) return;
    result.add(CategorySuggestion(category: category, reason: reason, keyword: keyword));
  }

  final byName = <(int, int, ServiceCategory)>[];
  for (var i = 0; i < categories.length; i++) {
    final rank = _nameRank(categories[i].label, text);
    if (rank != null) byName.add((rank, i, categories[i]));
  }
  byName.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  for (final match in byName) {
    add(match.$3, SuggestionReason.name);
  }

  for (final slug in remote.categories) {
    add(bySlug[slug], SuggestionReason.description);
  }
  for (final hit in remote.keywords) {
    add(bySlug[hit.category], SuggestionReason.keyword, hit.keyword);
  }

  return result.take(maxCategorySuggestions).toList();
}
