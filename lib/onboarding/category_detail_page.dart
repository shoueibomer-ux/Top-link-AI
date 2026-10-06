import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/coming_soon_badge.dart';
import '../widgets/pressable.dart';
import 'service_category.dart';

/// Full-page category preview, pushed when a category card is tapped on the
/// onboarding category step. Pops with `true` if the user taps "Select this
/// category" (the onboarding screen then advances to the urgency step), or
/// with no result on back navigation.
class CategoryDetailPage extends StatelessWidget {
  const CategoryDetailPage({super.key, required this.category});

  final ServiceCategory category;

  @override
  Widget build(BuildContext context) {
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
                    child: Text(
                      category.isLaunched ? 'Select this category' : 'Join the waitlist',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
              if (!category.isLaunched) const ComingSoonBadge(),
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
          _SectionLabel(category.isLaunched ? 'How it works' : 'Coming soon'),
          const SizedBox(height: 6),
          Text(
            category.isLaunched
                ? category.howItWorks
                : "This service isn't open in your area yet. Join the waitlist and "
                    "we'll save your request and contact you when it opens.",
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

