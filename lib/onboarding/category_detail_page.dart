import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/match_result.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/pressable.dart';
import '../widgets/provider_card.dart';
import 'service_category.dart';

/// Full-page category preview, pushed when a category card is tapped on the
/// onboarding category step. Pops with `true` if the user taps "Select this
/// category" (the onboarding screen then advances to the urgency step), or
/// with no result on back navigation.
class CategoryDetailPage extends StatefulWidget {
  const CategoryDetailPage({super.key, required this.category});

  final ServiceCategory category;

  @override
  State<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends State<CategoryDetailPage> {
  final _apiClient = ApiClient();
  late final Future<List<MatchResult>> _providersFuture;

  // Populated once the future resolves — kept mutable (separate from the
  // FutureBuilder's own snapshot) so "not interested" can remove a card
  // from view via setState without re-fetching.
  List<MatchResult>? _providers;

  @override
  void initState() {
    super.initState();
    // Uses the same demo location the location step prefills — the real
    // location isn't chosen yet at this point in onboarding.
    _providersFuture = _apiClient
        .getProvidersForCategory(
          category: widget.category.slug,
          lat: ApiClient.demoLat,
          lng: ApiClient.demoLng,
        )
        .then((providers) {
      if (mounted) setState(() => _providers = providers);
      return providers;
    });
  }

  void _dismiss(MatchResult match) {
    setState(() => _providers?.remove(match));
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: Text(category.label)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _CategoryHeader(category: category),
                  const SizedBox(height: 28),
                  const Text(
                    'Available providers',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FutureBuilder<List<MatchResult>>(
                    future: _providersFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: CircularProgressIndicator(color: AppColors.turquoise),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return _MessageCard(
                          text: 'Could not load providers right now. Pull up this category again later to see who is available.',
                        );
                      }
                      final providers = _providers!;
                      if (providers.isEmpty) {
                        return const _MessageCard(
                          text: "No providers found nearby yet — we'll notify you as soon as one is available.",
                        );
                      }
                      return Column(
                        children: [
                          for (final match in providers) ...[
                            ProviderCard(match: match, onDismiss: () => _dismiss(match)),
                            const SizedBox(height: 14),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Pressable(
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.turquoise,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                    ),
                    child: const Text(
                      'Select this category',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category});

  final ServiceCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.turquoise.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(category.icon, color: AppColors.turquoise, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  category.label,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SectionLabel('What we cover'),
          const SizedBox(height: 6),
          Text(
            category.whatWeCover,
            style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.navy),
          ),
          const SizedBox(height: 16),
          _SectionLabel('How it works'),
          const SizedBox(height: 6),
          Text(
            category.howItWorks,
            style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.navy),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: AppColors.turquoise,
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Text(text, style: TextStyle(fontSize: 14, color: AppColors.muted)),
    );
  }
}
