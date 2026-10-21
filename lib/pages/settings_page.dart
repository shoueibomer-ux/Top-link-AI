import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/auth_models.dart';
import '../app_colors.dart';
import '../account/delete_account.dart';
import '../app_styles.dart';
import '../legal/legal_pages.dart';
import '../onboarding/onboarding_screen.dart';
import '../messaging/push_service.dart';
import '../provider/auth_storage.dart';
import '../provider/provider_session.dart';
import '../widgets/app_drawer.dart';

const _appVersion = '1.0.0';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Settings')),
      drawer: const AppDrawer(),
      body: const SafeArea(child: SettingsBody()),
    );
  }
}

/// The settings content on its own, so it can be embedded either inside the
/// standalone [SettingsPage] (reached from the drawer) or directly as a tab
/// body (the home screen's bottom-nav Profile tab), without duplicating the
/// notifications/language/logout logic in two places.
class SettingsBody extends StatefulWidget {
  const SettingsBody({super.key, this.api, this.openUrl = openInBrowser, this.afterDeleted});

  /// Tests pass a client backed by a fake HTTP layer.
  final ApiClient? api;

  /// Opens a legal page in the browser, and what the app does once an account has been deleted. Tests replace both.
  final UrlOpener openUrl;
  final Future<void> Function(BuildContext context)? afterDeleted;

  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  bool _notificationsEnabled = false;
  bool _notificationsBusy = false;
  String _language = 'English';

  /// Who is signed in, for the card at the top: null until loaded or when nobody is.
  AccountProfile? _account;
  bool _accountLoaded = false;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _loadAccount();
  }

  Future<void> _loadNotifications() async {
    final on = await PushService.instance.notificationsOn();
    if (mounted) setState(() => _notificationsEnabled = on);
  }

  Future<void> _loadAccount() async {
    AccountProfile? account;
    var signedIn = false;
    try {
      signedIn = await AuthStorage.isLoggedIn();
      if (signedIn) {
        final session = AuthSession(api: widget.api);
        account = await session.authorized(session.api.getMe);
      }
    } catch (_) {
      // Settings still works without the account card.
    }
    if (mounted) {
      setState(() {
        _account = account;
        _signedIn = signedIn;
        _accountLoaded = true;
      });
    }
  }

  Future<void> _setNotifications(bool wanted) async {
    if (_notificationsBusy) return;
    setState(() => _notificationsBusy = true);
    final on = await PushService.instance.setNotifications(wanted);
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = on;
      _notificationsBusy = false;
    });
    if (wanted && !on) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Notifications are off for Tabmatch on this phone. Turn them on in your phone's settings.")),
      );
    }
  }

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

  Future<void> _deleteAccount() => startDeleteAccount(
        context,
        session: AuthSession(api: widget.api),
        isProvider: _account?.role == 'provider',
        afterDeleted: widget.afterDeleted,
      );

  Future<void> _logOut() async {
    // Actually end the provider session first: this used to just re-route,
    // leaving the stored access/refresh tokens in place, so "Log out" logged
    // nobody out.
    await PushService.instance.unregister(); // before the login goes, so the server can be told
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (_accountLoaded) _AccountCard(account: _account),
        const _SectionHeader('Preferences'),
        _SettingsCard(
          children: [
            _SettingsSwitchTile(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              value: _notificationsEnabled,
              onChanged: _setNotifications,
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
              key: const Key('link-privacy'),
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              onTap: () => openLegalPage(context, LegalPage.privacy, open: widget.openUrl),
            ),
            _SettingsTile(
              key: const Key('link-terms'),
              icon: Icons.description_outlined,
              title: 'Terms of Service',
              onTap: () => openLegalPage(context, LegalPage.terms, open: widget.openUrl),
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
            if (_signedIn)
              _SettingsTile(
                key: const Key('delete-account'),
                icon: Icons.delete_outline,
                title: 'Delete my account',
                onTap: _deleteAccount,
                showChevron: false,
                destructive: true,
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
    );
  }
}

/// Who is signed in: their name and email, or a note that nobody is.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});

  final AccountProfile? account;

  @override
  Widget build(BuildContext context) {
    final name = account?.fullName.trim() ?? '';
    final initial = (name.isNotEmpty ? name : (account?.email ?? '?')).characters.first.toUpperCase();
    return Container(
      key: const Key('account-card'),
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(kRadius), boxShadow: kCardShadow),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.turquoise.withValues(alpha: 0.15),
            child: account == null
                ? const Icon(Icons.person_outline, color: AppColors.navy)
                : Text(initial, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: account == null
                ? Text(
                    "You're not signed in. Sign in from History to keep your requests and chats with your Google account.",
                    key: const Key('account-signed-out'),
                    style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.mutedText),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (name.isNotEmpty)
                        Text(name, key: const Key('account-name'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy)),
                      Text(account!.email, key: const Key('account-email'), style: TextStyle(fontSize: 14, color: AppColors.mutedText)),
                    ],
                  ),
          ),
        ],
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
      // The tiles paint their tap ripple on the nearest Material, and the
      // card's DecoratedBox (which has a background colour) would otherwise
      // be it — hiding every ripple. Flutter asserts about exactly this.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Color(0xFFE1E8EF), indent: 20),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.trailingText,
    this.showChevron = true,
    this.destructive = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? trailingText;
  final bool showChevron;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: destructive ? const Color(0xFFBA1A1A) : AppColors.navy),
      title: Text(title, style: TextStyle(color: destructive ? const Color(0xFFBA1A1A) : AppColors.navy, fontWeight: FontWeight.w500)),
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
