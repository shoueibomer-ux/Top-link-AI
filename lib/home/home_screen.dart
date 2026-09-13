import 'package:flutter/material.dart';

import '../api/match_result.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/service_category.dart';
import '../onboarding/urgency_step.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_logo.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.category,
    required this.urgency,
    required this.matches,
  });

  final ServiceCategory category;
  final Urgency urgency;
  final List<MatchResult> matches;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const AppLogo()),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              "You're all set!",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "We're matching you with top ${category.label.toLowerCase()} providers in your area.",
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
            const SizedBox(height: 28),
            _RequestSummaryCard(category: category, urgency: urgency),
            const SizedBox(height: 32),
            const Text(
              'Recommended providers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 14),
            if (matches.isEmpty)
              const _EmptyProvidersNotice()
            else
              for (final match in matches) ...[
                _ProviderCard(match: match),
                const SizedBox(height: 14),
              ],
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  );
                },
                child: const Text(
                  'Start a new request',
                  style: TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestSummaryCard extends StatelessWidget {
  const _RequestSummaryCard({required this.category, required this.urgency});

  final ServiceCategory category;
  final Urgency urgency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Row(
        children: [
          _IconBadge(icon: category.icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(urgency.icon, size: 14, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Text(
                      urgency.label,
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.turquoise.withValues(alpha: 0.12),
      child: Icon(icon, color: AppColors.turquoise),
    );
  }
}

class _EmptyProvidersNotice extends StatelessWidget {
  const _EmptyProvidersNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Text(
        "No providers found nearby yet — we'll notify you as soon as one is available.",
        style: TextStyle(fontSize: 14, color: AppColors.muted),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.match});

  final MatchResult match;

  @override
  Widget build(BuildContext context) {
    final profile = match.profile;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.turquoise.withValues(alpha: 0.12),
            child: Text(
              '${match.score.round()}%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.turquoise,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star, size: 14, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      '${profile.rating} · ${match.distanceKm} km away',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.navy),
        ],
      ),
    );
  }
}
