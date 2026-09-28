/// Response from GET /api/categories/suggest/ (matching.views.
/// CategorySuggestView) — what the backend's keyword classifier makes of
/// partly-typed search text. No AI call is involved on the server.
class RemoteCategorySuggestions {
  const RemoteCategorySuggestions({this.categories = const [], this.keywords = const []});

  factory RemoteCategorySuggestions.fromJson(Map<String, dynamic> json) {
    return RemoteCategorySuggestions(
      categories: [for (final slug in json['categories'] as List<dynamic>? ?? const []) slug as String],
      keywords: [
        for (final entry in json['keywords'] as List<dynamic>? ?? const [])
          KeywordSuggestion(
            keyword: (entry as Map<String, dynamic>)['keyword'] as String,
            category: entry['category'] as String,
          ),
      ],
    );
  }

  static const none = RemoteCategorySuggestions();

  /// Category slugs the whole text points at, best match first.
  final List<String> categories;

  /// Taxonomy keywords the text is heading toward, each mapped to a category.
  final List<KeywordSuggestion> keywords;
}

class KeywordSuggestion {
  const KeywordSuggestion({required this.keyword, required this.category});

  final String keyword;
  final String category;
}
