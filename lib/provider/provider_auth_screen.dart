import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/auth_models.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import 'auth_storage.dart';
import 'provider_business_profile_screen.dart';

/// Real login/register for a provider account (accounts.views.RegisterView /
/// LoginView) — the marketplace build plan's Phase 1A entry point for new
/// providers, replacing the self-issued-UUID onboarding wizard as the
/// default path. The wizard (provider_onboarding_screen.dart) is left
/// reachable from the drawer, unchanged, for anyone still using it.
class ProviderAuthScreen extends StatefulWidget {
  const ProviderAuthScreen({super.key});

  @override
  State<ProviderAuthScreen> createState() => _ProviderAuthScreenState();
}

class _ProviderAuthScreenState extends State<ProviderAuthScreen> {
  final _apiClient = ApiClient();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _businessNameController = TextEditingController();

  bool _isRegister = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _businessNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tokens = _isRegister
          ? await _apiClient.register(
              email: email,
              password: password,
              role: UserRole.provider,
              fullName: _fullNameController.text.trim(),
              businessName: _businessNameController.text.trim(),
            )
          : await _apiClient.login(email: email, password: password);

      await AuthStorage.save(access: tokens.access, refresh: tokens.refresh);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProviderBusinessProfileScreen()),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong — try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: Text(_isRegister ? 'Create Business Account' : 'Provider Login')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _isRegister ? 'Create your business account' : 'Welcome back',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navy),
            ),
            const SizedBox(height: 6),
            Text(
              _isRegister
                  ? 'One account for your business profile, leads, and reviews.'
                  : 'Sign in to manage your business profile and leads.',
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            if (_isRegister) ...[
              _AuthField(label: 'Your name', controller: _fullNameController),
              _AuthField(label: 'Business name', controller: _businessNameController),
            ],
            _AuthField(label: 'Email', controller: _emailController, keyboardType: TextInputType.emailAddress),
            _AuthField(label: 'Password', controller: _passwordController, obscureText: true),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.turquoise,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                      )
                    : Text(_isRegister ? 'Create account' : 'Log in', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _loading ? null : () => setState(() => _isRegister = !_isRegister),
                child: Text(
                  _isRegister ? 'Already have an account? Log in' : 'New provider? Create an account',
                  style: const TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;

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
              obscureText: obscureText,
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
