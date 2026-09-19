import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../pages/about_us_page.dart';
import '../pages/mission_vision_page.dart';
import '../pages/settings_page.dart';
import '../provider/auth_storage.dart';
import '../provider/provider_auth_screen.dart';
import '../provider/provider_business_profile_screen.dart';
import '../provider/provider_dashboard_screen.dart';
import '../provider/provider_onboarding_screen.dart';
import 'app_logo.dart';
import 'pressable.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.lightBackground,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          const _DrawerHeader(),
          const SizedBox(height: 12),
          _DrawerItem(
            icon: Icons.info_outline,
            label: 'About Us',
            onTap: () => _navigateTo(context, const AboutUsPage()),
          ),
          _DrawerItem(
            icon: Icons.flag_outlined,
            label: 'Mission & Vision',
            onTap: () => _navigateTo(context, const MissionVisionPage()),
          ),
          _DrawerItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => _navigateTo(context, const SettingsPage()),
          ),
          _DrawerItem(
            icon: Icons.business_center_outlined,
            label: 'Business Profile',
            onTap: () => _openBusinessProfile(context),
          ),
          _DrawerItem(
            icon: Icons.storefront_outlined,
            label: 'Provider Dashboard',
            onTap: () => _navigateTo(context, const ProviderDashboardScreen()),
          ),
          _DrawerItem(
            icon: Icons.assignment_outlined,
            label: 'Provider Sign-Up (demo)',
            onTap: () => _navigateTo(context, const ProviderOnboardingScreen()),
          ),
        ],
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  // The real, authenticated path (build plan Phase 1A) — goes straight to
  // the profile if already logged in, otherwise to login/register first.
  Future<void> _openBusinessProfile(BuildContext context) async {
    final loggedIn = await AuthStorage.isLoggedIn();
    if (!context.mounted) return;
    _navigateTo(context, loggedIn ? const ProviderBusinessProfileScreen() : const ProviderAuthScreen());
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
      color: AppColors.navy,
      child: const Align(
        alignment: Alignment.centerLeft,
        child: AppLogo(height: 40),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Pressable(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: kCardShadow,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(kRadius),
              onTap: onTap,
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                leading: Icon(icon, color: AppColors.navy),
                title: Text(
                  label,
                  style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
