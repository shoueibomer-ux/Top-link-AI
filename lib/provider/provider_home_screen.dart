import 'package:flutter/material.dart';

import '../api/provider_profile.dart';
import '../app_colors.dart';
import '../widgets/app_logo.dart';
import 'provider_leads_tab.dart';
import 'provider_session.dart';
import 'provider_widgets.dart';

/// The provider's home once approved, in two tabs: their profile as clients'
/// matches will see it (with a way to edit it), and their leads.
class ProviderHomeScreen extends StatelessWidget {
  const ProviderHomeScreen({
    super.key,
    required this.profile,
    required this.session,
    required this.onEdit,
    required this.onRefresh,
    required this.onSignOut,
    required this.onSwitchRole,
    required this.onSessionExpired,
  });

  final ProviderProfileData profile;
  final AuthSession session;
  final VoidCallback onSessionExpired;
  final VoidCallback onEdit;
  final Future<void> Function() onRefresh;
  final VoidCallback onSignOut;
  final VoidCallback onSwitchRole;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.lightBackground,
        appBar: AppBar(
          title: const AppLogo(),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) =>
                  value == 'role' ? onSwitchRole() : onSignOut(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'role', child: Text('Switch role')),
                PopupMenuItem(value: 'out', child: Text('Sign out')),
              ],
            ),
          ],
          bottom: const TabBar(
            indicatorColor: AppColors.turquoise,
            labelColor: AppColors.white,
            unselectedLabelColor: Color(0xB3FFFFFF),
            tabs: [
              Tab(key: Key('tab-profile'), text: 'Profile'),
              Tab(key: Key('tab-leads'), text: 'Leads'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _profileTab(),
            ProviderLeadsTab(
              session: session,
              onSessionExpired: onSessionExpired,
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileTab() {
    return SafeArea(
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
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                StatusPill(profile.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "You're approved. Clients in your cities can be matched with you for the services below.",
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.muted,
              ),
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
    );
  }
}
