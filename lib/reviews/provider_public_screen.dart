import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/reviews.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../onboarding/service_category.dart';
import '../provider/provider_session.dart';
import '../widgets/stars.dart';
import 'review_ui.dart';

/// A provider's public page for clients: business name, average rating and review count, what they do and
/// where, every review with their reply, and a heart to save them to Favorites. Contact details are never here.
class ProviderPublicScreen extends StatefulWidget {
  const ProviderPublicScreen({super.key, required this.session, required this.providerId, this.providerName = ''});

  final AuthSession session;
  final int providerId;

  /// Shown in the title while the page loads.
  final String providerName;

  @override
  State<ProviderPublicScreen> createState() => _ProviderPublicScreenState();
}

class _ProviderPublicScreenState extends State<ProviderPublicScreen> {
  ProviderPage? _page;
  String? _error;
  bool _expired = false;
  bool _savingFavorite = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _expired = false;
    });
    try {
      final page = await widget.session.authorized((t) => widget.session.api.getProviderPage(t, widget.providerId));
      if (mounted) setState(() => _page = page);
    } on SessionExpiredException {
      if (mounted) setState(() => _expired = true);
    } catch (e) {
      if (mounted) setState(() => _error = reviewErrorText(e));
    }
  }

  Future<void> _toggleFavorite() async {
    final page = _page;
    if (page == null || _savingFavorite) return;
    final next = !page.isFavorite;
    setState(() {
      _savingFavorite = true;
      _page = ProviderPage(provider: page.provider, reviews: page.reviews, isFavorite: next);
    });
    try {
      await widget.session.authorized((t) => widget.session.api.setFavorite(t, widget.providerId, next));
    } catch (e) {
      if (!mounted) return;
      setState(() => _page = page); // put the heart back
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is SessionExpiredException ? 'Your session has expired. Please sign in again.' : reviewErrorText(e)),
      ));
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: Text(page?.provider.businessName ?? (widget.providerName.isEmpty ? 'Provider' : widget.providerName)),
        actions: [
          if (page != null)
            IconButton(
              key: const Key('favorite-toggle'),
              tooltip: page.isFavorite ? 'Remove from Favorites' : 'Save to Favorites',
              onPressed: _toggleFavorite,
              icon: Icon(page.isFavorite ? Icons.favorite : Icons.favorite_border, color: page.isFavorite ? const Color(0xFFFF6B81) : AppColors.white),
            ),
        ],
      ),
      body: SafeArea(child: _body(page)),
    );
  }

  Widget _body(ProviderPage? page) {
    if (_expired) return _message('Your session has expired. Please sign in again.');
    if (_error != null) {
      return _message(_error!, retry: true);
    }
    if (page == null) return const Center(child: CircularProgressIndicator(color: AppColors.turquoise));
    final provider = page.provider;
    final services = [for (final slug in provider.categories) findCategoryBySlug(slug)?.label ?? slug];
    return RefreshIndicator(
      color: AppColors.turquoise,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(kRadius), boxShadow: kCardShadow),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(provider.businessName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy)),
              const SizedBox(height: 6),
              KeyedSubtree(key: const Key('provider-rating'), child: RatingLine(rating: provider.rating, fontSize: 14)),
              if (services.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Line(icon: Icons.category_outlined, text: services.join(', ')),
              ],
              if (provider.cities.isNotEmpty) _Line(icon: Icons.location_on_outlined, text: provider.cities.join(', ')),
              if (provider.bio.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(provider.bio, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.navy)),
              ],
            ]),
          ),
          const SizedBox(height: 20),
          Text('Reviews', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
          const SizedBox(height: 10),
          if (page.reviews.isEmpty)
            Text('No reviews yet.', key: const Key('no-reviews'), style: TextStyle(fontSize: 14, color: AppColors.mutedText))
          else
            for (final review in page.reviews) ...[
              ReviewTile(
                review: review,
                onReport: review.mine ? null : () => reportReviewFlow(context, session: widget.session, review: review),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Widget _message(String text, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, key: const Key('provider-page-message'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.mutedText)),
          if (retry) TextButton(key: const Key('provider-page-retry'), onPressed: _load, child: const Text('Try again')),
        ]),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: AppColors.mutedText),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: AppColors.navy))),
      ]),
    );
  }
}
