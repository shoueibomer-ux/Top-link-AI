import 'package:flutter/material.dart';

import '../api/provider_profile.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../onboarding/service_category.dart';

/// Turquoise full-width button used across the provider screens.
class BrandButton extends StatelessWidget {
  const BrandButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final child = busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: outlined ? AppColors.turquoise : AppColors.white),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius));
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: outlined
          ? OutlinedButton(
              onPressed: enabled ? onPressed : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.turquoise,
                side: const BorderSide(color: AppColors.turquoise),
                shape: shape,
              ),
              child: child,
            )
          : ElevatedButton(
              onPressed: enabled ? onPressed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.turquoise,
                disabledBackgroundColor: AppColors.turquoise.withValues(alpha: 0.35),
                foregroundColor: AppColors.white,
                disabledForegroundColor: AppColors.white,
                elevation: 0,
                shape: shape,
              ),
              child: child,
            ),
    );
  }
}

/// "Pending review" / "Approved" / "Not approved" pill.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});

  final ProviderStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ProviderStatus.pending => ('Pending review', const Color(0xFFB45309)),
      ProviderStatus.approved => ('Approved', const Color(0xFF15803D)),
      ProviderStatus.rejected => ('Not approved', const Color(0xFFBA1A1A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// The provider's details, as they entered them.
class ProviderProfileCard extends StatelessWidget {
  const ProviderProfileCard({super.key, required this.profile});

  final ProviderProfileData profile;

  @override
  Widget build(BuildContext context) {
    final services = [for (final slug in profile.categories) findCategoryBySlug(slug)?.label ?? slug];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile.businessName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy),
          ),
          const SizedBox(height: 14),
          _Line(icon: Icons.phone_outlined, text: profile.phone),
          _Line(icon: Icons.email_outlined, text: profile.email),
          _Line(icon: Icons.category_outlined, text: services.join(', ')),
          _Line(icon: Icons.location_on_outlined, text: profile.cities.join(', ')),
          if (profile.bio.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(profile.bio, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.navy)),
          ],
        ],
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.turquoise),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: AppColors.navy))),
        ],
      ),
    );
  }
}
