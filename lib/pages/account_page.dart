import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/auth_models.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../provider/auth_storage.dart';
import '../provider/provider_auth_screen.dart';

/// Settings -> Account: lets a signed-in account holder edit their own name and
/// sign-in email (PATCH /api/accounts/me/ — see accounts.serializers.
/// ProfileUpdateSerializer for what is deliberately not editable).
///
/// The app is anonymous by default — customers browse and unlock providers by
/// device, with no account — so most people will see the "no account" state
/// here, which says so plainly instead of pretending there's a profile to edit.
/// The only sign-in the app offers today is a business (provider) account.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, this.apiClient});

  /// Injectable for tests; defaults to a real client.
  final ApiClient? apiClient;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

enum _AccountState { loading, loggedOut, sessionExpired, loadError, ready }

class _AccountPageState extends State<AccountPage> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  _AccountState _state = _AccountState.loading;
  AccountProfile? _profile;
  String? _accessToken;
  String? _loadError;
  String? _saveError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _state = _AccountState.loading);
    final token = await AuthStorage.getAccessToken();
    if (!mounted) return;
    if (token == null) {
      setState(() => _state = _AccountState.loggedOut);
      return;
    }
    try {
      final profile = await _api.getMe(token);
      if (!mounted) return;
      setState(() {
        _accessToken = token;
        _profile = profile;
        _nameController.text = profile.fullName;
        _emailController.text = profile.email;
        _saveError = null;
        _state = _AccountState.ready;
      });
    } on SessionExpiredException {
      if (mounted) setState(() => _state = _AccountState.sessionExpired);
    } on ApiException catch (e) {
      _showLoadError(e.message);
    } catch (_) {
      _showLoadError('Could not load your account. Check your connection and try again.');
    }
  }

  void _showLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _loadError = message;
      _state = _AccountState.loadError;
    });
  }

  Future<void> _goToLogin({bool clearFirst = false}) async {
    if (clearFirst) await AuthStorage.clear();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProviderAuthScreen()));
    if (mounted) _load();
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _hasChanges =>
      _profile != null &&
      (_nameController.text.trim() != _profile!.fullName || _emailController.text.trim() != _profile!.email);

  Future<void> _save() async {
    final profile = _profile;
    final token = _accessToken;
    if (profile == null || token == null) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _saveError = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final updated = await _api.updateMe(
        accessToken: token,
        fullName: name != profile.fullName ? name : null,
        email: email != profile.email ? email : null,
      );
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _nameController.text = updated.fullName;
        _emailController.text = updated.email;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account updated.')));
    } on SessionExpiredException {
      if (mounted) setState(() => _state = _AccountState.sessionExpired);
    } on ApiException catch (e) {
      if (mounted) setState(() => _saveError = e.message);
    } catch (_) {
      if (mounted) setState(() => _saveError = 'Could not save your changes — try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: switch (_state) {
          _AccountState.loading =>
            const Center(child: CircularProgressIndicator(color: AppColors.turquoise)),
          _AccountState.loggedOut => _MessageCard(
              icon: Icons.person_outline,
              title: "You're browsing without an account",
              message: 'Your requests and unlocked providers are saved on this device, so there is no '
                  'profile to edit. Business owners can log in or create a business account to manage '
                  'their listing and reply to customer requests.',
              actionLabel: 'Log in or create a business account',
              onAction: () => _goToLogin(),
            ),
          _AccountState.sessionExpired => _MessageCard(
              icon: Icons.lock_clock_outlined,
              title: 'Your session has expired',
              message: 'For your security you were signed out. Log in again to edit your account.',
              actionLabel: 'Log in again',
              onAction: () => _goToLogin(clearFirst: true),
            ),
          _AccountState.loadError => _MessageCard(
              icon: Icons.cloud_off_outlined,
              title: "Couldn't load your account",
              message: _loadError ?? 'Something went wrong.',
              actionLabel: 'Retry',
              onAction: _load,
            ),
          _AccountState.ready => _buildForm(),
        },
      ),
    );
  }

  Widget _buildForm() {
    final isProvider = _profile?.role == UserRole.provider;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.turquoise.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isProvider ? 'Business account' : 'Customer account',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _AccountField(
          label: 'Full name',
          controller: _nameController,
          onChanged: (_) => setState(() {}),
        ),
        _AccountField(
          label: 'Email',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
        ),
        Text(
          'Your email is what you log in with.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 12),
          Text(_saveError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_saving || !_hasChanges) ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.turquoise,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
            ),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                  )
                : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _AccountField extends StatelessWidget {
  const _AccountField({required this.label, required this.controller, this.keyboardType, this.onChanged});

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(kRadius),
              boxShadow: kCardShadow,
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              onChanged: onChanged,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: kCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 36, color: AppColors.turquoise),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
              const SizedBox(height: 8),
              Text(message, style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.turquoise,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                  ),
                  child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
