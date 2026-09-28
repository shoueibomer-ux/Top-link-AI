import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/category_suggestions.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../chat/chat_screen.dart';
import '../onboarding/category_detail_page.dart';
import '../onboarding/category_search.dart';
import '../onboarding/service_category.dart';
import 'pressable.dart';

/// Looks up the backend's keyword suggestions for partly-typed text. A
/// parameter so tests can supply canned answers instead of the network.
typedef CategorySuggestionsFetcher = Future<RemoteCategorySuggestions> Function(String query);

/// A search field pinned at the top of [child]'s area, with the search
/// behaviour that goes with it.
///
/// The field stays put (it is outside whatever scrolls). While it has text,
/// matching categories (see [buildCategorySuggestions]) replace [child] —
/// which stays alive underneath, so its scroll position survives — and picking
/// one, or submitting the search, opens that category's CategoryDetailPage
/// directly, skipping the group and service lists. Confirming there ("Select
/// this category") calls [onSelect].
class CategorySearchView extends StatefulWidget {
  const CategorySearchView({
    super.key,
    required this.child,
    required this.onSelect,
    this.suggestionsFetcher,
    this.padding = EdgeInsets.zero,
  });

  /// What is shown below the field when there's no search text.
  final Widget child;

  /// Called with the category once the user confirms it on its detail page.
  final ValueChanged<ServiceCategory> onSelect;

  /// Defaults to [ApiClient.suggestCategories].
  final CategorySuggestionsFetcher? suggestionsFetcher;

  /// Space around the field; the results list uses the same sides.
  final EdgeInsets padding;

  @override
  State<CategorySearchView> createState() => _CategorySearchViewState();
}

class _CategorySearchViewState extends State<CategorySearchView> {
  /// How long typing must pause before the backend is asked — keeps a burst of
  /// keystrokes to one request.
  static const _typingPause = Duration(milliseconds: 300);

  final _controller = TextEditingController();
  Timer? _debounce;

  // The backend's answer for [_remoteQuery]; stale until a newer one lands, so
  // the list doesn't blank out between keystrokes.
  RemoteCategorySuggestions _remote = RemoteCategorySuggestions.none;
  String _remoteQuery = '';
  bool _remoteFailed = false;
  bool _remoteLoading = false;

  // Bumped per request so a slow, older answer can't overwrite a newer one.
  int _requestId = 0;

  late final CategorySuggestionsFetcher _fetchSuggestions =
      widget.suggestionsFetcher ?? ApiClient().suggestCategories;

  @override
  void initState() {
    super.initState();
    loadCatalogFromApi().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get _query => normalizeSearchQuery(_controller.text);

  // Text too short to mean anything isn't sent to the backend (it would return
  // nothing), so its "answer" is trivially complete.
  bool _worthAsking(String query) => query.length >= 2;

  List<CategorySuggestion> get _suggestions => buildCategorySuggestions(
        _query,
        serviceCategories,
        // Only trust the backend's answer while it still matches what's typed
        // (or is a prefix of it): otherwise "pipe" answers would linger under
        // "electric".
        _query.startsWith(_remoteQuery) && _remoteQuery.isNotEmpty ? _remote : RemoteCategorySuggestions.none,
      );

  void _onChanged(String _) {
    _debounce?.cancel();
    final query = _query;
    if (!_worthAsking(query)) {
      _requestId++; // drop anything in flight
      setState(() {
        _remote = RemoteCategorySuggestions.none;
        _remoteQuery = '';
        _remoteFailed = false;
        _remoteLoading = false;
      });
      return;
    }
    setState(() => _remoteLoading = true);
    _debounce = Timer(_typingPause, () => _askBackend(query));
  }

  Future<void> _askBackend(String query) async {
    final id = ++_requestId;
    try {
      final answer = await _fetchSuggestions(query);
      if (!mounted || id != _requestId) return;
      setState(() {
        _remote = answer;
        _remoteQuery = query;
        _remoteFailed = false;
        _remoteLoading = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      // Name matches still work without the backend; just say so.
      setState(() {
        _remote = RemoteCategorySuggestions.none;
        _remoteQuery = '';
        _remoteFailed = true;
        _remoteLoading = false;
      });
    }
  }

  /// Keyboard "search": ask the backend now (no waiting out the typing pause)
  /// and jump to the best match. With no match, the empty state stays up.
  Future<void> _submit() async {
    final query = _query;
    if (query.isEmpty) return;
    _debounce?.cancel();
    if (_worthAsking(query)) {
      setState(() => _remoteLoading = true);
      await _askBackend(query);
      if (!mounted || query != _query) return;
    }
    final suggestions = _suggestions;
    if (suggestions.isNotEmpty) await _openService(suggestions.first.category);
  }

  /// The shortcut: straight to the category's detail page (provider results),
  /// not via the group / service lists. Confirming there selects the category
  /// just as it does when reached through the grid.
  Future<void> _openService(ServiceCategory service) async {
    FocusScope.of(context).unfocus();
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CategoryDetailPage(category: service)),
    );
    if (confirmed == true) widget.onSelect(service);
  }

  void _openAskAi() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.lightBackground,
          appBar: AppBar(title: const Text('Ask AI')),
          body: const SafeArea(child: ChatScreen()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: widget.padding,
          child: _SearchField(
            controller: _controller,
            onChanged: _onChanged,
            onSubmitted: (_) => _submit(),
            onClear: () {
              _controller.clear();
              _onChanged('');
            },
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              // Kept alive but hidden while searching, so clearing the search
              // returns to the same scroll position.
              Offstage(offstage: searching, child: widget.child),
              if (searching)
                Padding(
                  padding: widget.padding.copyWith(top: 16, bottom: 0),
                  child: _SearchResults(
                    query: _query,
                    suggestions: _suggestions,
                    loading: _remoteLoading,
                    offline: _remoteFailed,
                    onSelect: (suggestion) => _openService(suggestion.category),
                    onAskAi: _openAskAi,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 16, color: AppColors.navy),
        decoration: InputDecoration(
          // No hint text: the field is just the search icon until the user types.
          // The label is for screen readers only; nothing extra is drawn.
          prefixIcon: const Icon(Icons.search, color: AppColors.turquoise, semanticLabel: 'Search services'),
          // Rebuilds with the controller so the clear button appears and
          // disappears as text does, without the parent having to.
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close, size: 20, color: AppColors.mutedText),
                    onPressed: onClear,
                  ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

/// What replaces the grid while there's text in the search field: matching
/// categories, or — with none — a nudge toward Ask AI for open-ended requests.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.suggestions,
    required this.loading,
    required this.offline,
    required this.onSelect,
    required this.onAskAi,
  });

  final String query;
  final List<CategorySuggestion> suggestions;
  final bool loading;
  final bool offline;
  final ValueChanged<CategorySuggestion> onSelect;
  final VoidCallback onAskAi;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      // Still waiting on the backend: say nothing yet rather than flash "no
      // matches" and then replace it.
      if (loading) {
        return const Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: 32),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.turquoise),
            ),
          ),
        );
      }
      return _NoMatches(query: query, offline: offline, onAskAi: onAskAi);
    }
    return ListView.separated(
      itemCount: suggestions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _SuggestionTile(
        suggestion: suggestions[index],
        query: query,
        onTap: () => onSelect(suggestions[index]),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion, required this.query, required this.onTap});

  final CategorySuggestion suggestion;
  final String query;
  final VoidCallback onTap;

  String? get _subtitle => switch (suggestion.reason) {
        SuggestionReason.name => null,
        SuggestionReason.description => 'Matches "$query"',
        SuggestionReason.keyword => 'Keyword: ${suggestion.keyword}',
      };

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle;
    return Pressable(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(kRadius),
          boxShadow: kCardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(kRadius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.turquoise.withValues(alpha: 0.12),
                    child: Icon(suggestion.category.icon, size: 20, color: AppColors.turquoise),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestion.category.label,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy),
                        ),
                        if (subtitle != null)
                          Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.mutedText)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.mutedText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query, required this.offline, required this.onAskAi});

  final String query;
  final bool offline;
  final VoidCallback onAskAi;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 40, color: AppColors.mutedText),
          const SizedBox(height: 12),
          Text(
            'No categories match "$query"',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.navy),
          ),
          const SizedBox(height: 8),
          Text(
            "For a more open-ended request, describe it to Ask AI and we'll find the right providers.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.muted),
          ),
          if (offline) ...[
            const SizedBox(height: 8),
            Text(
              'Keyword suggestions are unavailable right now, so only category names were checked.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.mutedText),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onAskAi,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Ask AI'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.turquoise,
              side: const BorderSide(color: AppColors.turquoise),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
            ),
          ),
        ],
      ),
    );
  }
}
