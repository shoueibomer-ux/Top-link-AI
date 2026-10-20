import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/reviews.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../onboarding/service_category.dart';
import '../provider/auth_storage.dart';
import '../provider/provider_session.dart';
import '../widgets/stars.dart';
import 'provider_public_screen.dart';
import 'review_ui.dart';

/// The providers this client saved with the heart. Tap one for their page (rating, reviews); the heart there
/// removes them.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, this.api});

  final ApiClient? api;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late final AuthSession _session = AuthSession(api: widget.api);
  List<PublicProviderInfo>? _favorites;
  String? _error;
  bool _signedOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _signedOut = false;
    });
    try {
      if (!await AuthStorage.isLoggedIn()) {
        if (mounted) setState(() => _signedOut = true);
        return;
      }
      final favorites = await _session.authorized(_session.api.getFavorites);
      if (mounted) setState(() => _favorites = favorites);
    } on SessionExpiredException {
      if (mounted) setState(() => _signedOut = true);
    } catch (e) {
      if (mounted) setState(() => _error = reviewErrorText(e));
    }
  }

  Future<void> _open(PublicProviderInfo provider) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ProviderPublicScreen(session: _session, providerId: provider.id, providerName: provider.businessName),
    ));
    if (mounted) _load(); // the heart may have been removed there
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Favorites')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_signedOut) return _note(Icons.lock_outline, 'Sign in to see your favorites. Open History and sign in with Google.');
    if (_error != null) {
      return _note(Icons.error_outline, _error!, retry: true);
    }
    final favorites = _favorites;
    if (favorites == null) return const Center(child: CircularProgressIndicator(color: AppColors.turquoise));
    if (favorites.isEmpty) {
      return _note(Icons.favorite_border, 'No favorites yet. Tap the heart on a provider’s page to save them here.');
    }
    return RefreshIndicator(
      color: AppColors.turquoise,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final provider in favorites) ...[
            _FavoriteCard(provider: provider, onTap: () => _open(provider)),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(text, key: const Key('favorites-message'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.muted)),
          if (retry) TextButton(key: const Key('favorites-retry'), onPressed: _load, child: const Text('Try again')),
        ]),
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.provider, required this.onTap});

  final PublicProviderInfo provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final services = [for (final slug in provider.categories) findCategoryBySlug(slug)?.label ?? slug];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('favorite-${provider.id}'),
        borderRadius: BorderRadius.circular(kRadius),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(kRadius), boxShadow: kCardShadow),
          child: Row(children: [
            const Icon(Icons.favorite, color: Color(0xFFFF6B81)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(provider.businessName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy)),
                const SizedBox(height: 4),
                RatingLine(rating: provider.rating),
                if (services.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(services.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.mutedText)),
                ],
              ]),
            ),
            Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}
