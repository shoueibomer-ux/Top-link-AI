import 'package:flutter/material.dart';

import '../api/provider_profile.dart';
import '../app_colors.dart';
import '../widgets/app_logo.dart';
import 'provider_widgets.dart';

/// The provider's home once approved: their profile as clients' matches will
/// see it, with a way to edit it.
class ProviderHomeScreen extends StatelessWidget {
  const ProviderHomeScreen({
    super.key,
    required this.profile,
    required this.onEdit,
    required this.onRefresh,
    required this.onSignOut,
    required this.onSwitchRole,
  });

  final ProviderProfileData profile;
  final VoidCallback onEdit;
  final Future<void> Function() onRefresh;
  final VoidCallback onSignOut;
  final VoidCallback onSwitchRole;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const AppLogo(),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => value == 'role' ? onSwitchRole() : onSignOut(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'role', child: Text('Switch role')),
              PopupMenuItem(value: 'out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.turquoise,
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Your profile',
                      key: Key('provider-home-title'),
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navy),
                    ),
                  ),
                  StatusPill(profile.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "You're approved. Clients in your cities can be matched with you for the services below.",
                style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              ProviderProfileCard(profile: profile),
              const SizedBox(height: 24),
              BrandButton(
                key: const Key('edit-profile'),
                label: 'Edit profile',
                icon: Icons.edit_outlined,
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
