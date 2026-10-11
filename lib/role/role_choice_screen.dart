import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/app_logo.dart';
import '../widgets/pressable.dart';
import 'app_role.dart';

/// The first screen on a fresh install: are you here to get a service, or to
/// offer one? The answer is remembered (see [RoleStorage]).
class RoleChoiceScreen extends StatelessWidget {
  const RoleChoiceScreen({super.key, required this.onChosen});

  final ValueChanged<AppRole> onChosen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const AppLogo(height: 44, onLight: true),
              const SizedBox(height: 32),
              const Text(
                'Welcome to Tabmatch',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.navy),
              ),
              const SizedBox(height: 8),
              Text(
                'How would you like to use the app?',
                style: TextStyle(fontSize: 15, color: AppColors.muted),
              ),
              const SizedBox(height: 32),
              _RoleCard(
                key: const Key('role-client'),
                icon: Icons.search,
                title: 'I need a service',
                subtitle: 'Tell us what you need and we will connect you with local providers.',
                filled: false,
                onTap: () => onChosen(AppRole.client),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                key: const Key('role-provider'),
                icon: Icons.business_center_outlined,
                title: "I'm a service provider",
                subtitle: 'Register your business and get matched with clients in your city.',
                filled: true,
                onTap: () => onChosen(AppRole.provider),
              ),
              const Spacer(),
              Center(
                child: Text(
                  'You can switch any time from the menu.',
                  style: TextStyle(fontSize: 12, color: AppColors.mutedText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = filled ? AppColors.navy : AppColors.white;
    final foreground = filled ? AppColors.white : AppColors.navy;
    return Pressable(
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(kRadius),
          boxShadow: kCardShadow,
          border: filled ? null : Border.all(color: AppColors.navy.withValues(alpha: 0.15)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(kRadius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: AppColors.turquoise.withValues(alpha: 0.18), shape: BoxShape.circle),
                    child: Icon(icon, color: AppColors.turquoise, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: foreground)),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 13, height: 1.4, color: foreground.withValues(alpha: 0.75)),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: foreground.withValues(alpha: 0.6)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
