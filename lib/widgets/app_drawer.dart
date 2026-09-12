import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../pages/placeholder_page.dart';
import 'app_logo.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const _DrawerHeader(),
          _DrawerItem(
            icon: Icons.info_outline,
            label: 'About Us',
            onTap: () => _openPlaceholder(
              context,
              title: 'About Us',
              icon: Icons.info_outline,
              description: "We're building the easiest way to find trusted "
                  'local service providers. More about our story is coming soon.',
            ),
          ),
          _DrawerItem(
            icon: Icons.flag_outlined,
            label: 'Mission & Vision',
            onTap: () => _openPlaceholder(
              context,
              title: 'Mission & Vision',
              icon: Icons.flag_outlined,
              description: 'Our mission and vision statement is coming soon.',
            ),
          ),
          _DrawerItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => _openPlaceholder(
              context,
              title: 'Settings',
              icon: Icons.settings_outlined,
              description: 'App settings and preferences are coming soon.',
            ),
          ),
        ],
      ),
    );
  }

  void _openPlaceholder(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String description,
  }) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaceholderPage(title: title, icon: icon, description: description),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
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
    return ListTile(
      leading: Icon(icon, color: AppColors.navy),
      title: Text(
        label,
        style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
    );
  }
}
