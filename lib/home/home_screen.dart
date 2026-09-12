import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/service_category.dart';
import '../onboarding/urgency_step.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.category,
    required this.urgency,
  });

  final ServiceCategory category;
  final Urgency urgency;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Top Link AI')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              "You're all set!",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "We're matching you with top ${category.label.toLowerCase()} providers in your area.",
              style: TextStyle(fontSize: 14, color: AppColors.navy.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),
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
            const SizedBox(height: 12),
            for (final provider in _mockProviders) ...[
              _ProviderCard(provider: provider, category: category),
              const SizedBox(height: 12),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8EF)),
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
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(urgency.icon, size: 14, color: AppColors.navy.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Text(
                      urgency.label,
                      style: TextStyle(fontSize: 13, color: AppColors.navy.withValues(alpha: 0.6)),
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

class _MockProvider {
  const _MockProvider(this.name, this.rating, this.distanceKm);

  final String name;
  final double rating;
  final double distanceKm;
}

const _mockProviders = [
  _MockProvider('Ahmed Plumbing Co.', 4.6, 2.1),
  _MockProvider('QuickFix Pros', 4.8, 3.4),
  _MockProvider('Reliable Home Services', 4.5, 5.0),
];

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.provider, required this.category});

  final _MockProvider provider;
  final ServiceCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8EF)),
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
                  provider.name,
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
                      '${provider.rating} · ${provider.distanceKm} km away',
                      style: TextStyle(fontSize: 13, color: AppColors.navy.withValues(alpha: 0.6)),
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
