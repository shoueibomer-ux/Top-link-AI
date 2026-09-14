import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../subscription/app_entry_point.dart';
import '../widgets/app_drawer.dart';

const _appVersion = '1.0.0';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  String _language = 'English';

  Future<void> _pickLanguage() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: RadioGroup<String>(
          groupValue: _language,
          onChanged: (value) => Navigator.of(context).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Choose language',
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy, fontSize: 16),
                ),
              ),
              for (final option in const ['English', 'Arabic'])
                RadioListTile<String>(
                  value: option,
                  activeColor: AppColors.turquoise,
                  title: Text(option, style: const TextStyle(color: AppColors.navy)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      setState(() => _language = selected);
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming soon.')),
    );
  }

  void _logOut() {
    // Route back through the paywall gate (not straight to onboarding) so
    // subscription status is re-checked rather than assumed.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppEntryPoint()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Settings')),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            const _SectionHeader('Account'),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.person_outline,
                  title: 'Account',
                  subtitle: 'Edit profile and email',
                  onTap: () => _showComingSoon('Account editing'),
                ),
              ],
            ),
            const _SectionHeader('Preferences'),
            _SettingsCard(
              children: [
                _SettingsSwitchTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  value: _notificationsEnabled,
                  onChanged: (value) => setState(() => _notificationsEnabled = value),
                ),
                _SettingsTile(
                  icon: Icons.language_outlined,
                  title: 'Language',
                  trailingText: _language,
                  onTap: _pickLanguage,
                ),
              ],
            ),
            const _SectionHeader('Legal'),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () => _showComingSoon('Privacy Policy'),
                ),
                _SettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms of Service',
                  onTap: () => _showComingSoon('Terms of Service'),
                ),
              ],
            ),
            const _SectionHeader('Session'),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.logout,
                  title: 'Log out',
                  onTap: _logOut,
                  showChevron: false,
                ),
              ],
            ),
            const SizedBox(height: 28),
            Center(
              child: Text(
                'App version $_appVersion',
                style: TextStyle(fontSize: 13, color: AppColors.navy.withValues(alpha: 0.5)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: AppColors.navy.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFE1E8EF), indent: 20),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.showChevron = true,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final bool showChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: AppColors.navy),
      title: Text(title, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: AppColors.muted, fontSize: 13))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(trailingText!, style: TextStyle(color: AppColors.muted)),
          if (showChevron) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.navy),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: AppColors.navy),
      title: Text(title, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w500)),
      trailing: Switch(
        value: value,
        activeThumbColor: AppColors.turquoise,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }
}
