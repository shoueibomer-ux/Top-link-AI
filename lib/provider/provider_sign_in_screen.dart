import 'dart:async';

import 'package:flutter/material.dart';

import '../account/email_sign_in.dart';
import '../api/api_client.dart';
import '../api/provider_profile.dart';
import '../app_colors.dart';
import '../messaging/push_service.dart';
import '../widgets/app_logo.dart';
import 'auth_storage.dart';
import 'google_sign_in_service.dart';
import 'provider_widgets.dart';

/// Provider sign-in: "Continue with Google", and "Continue with email" when the server can send codes. The Google ID token
/// goes to the backend, which verifies it and answers with this provider's own
/// tokens (and their profile, if they've already registered).
class ProviderSignInScreen extends StatefulWidget {
  const ProviderSignInScreen({
    super.key,
    required this.api,
    required this.idTokenProvider,
    required this.onSignedIn,
    required this.onSwitchRole,
    this.message,
  });

  final ApiClient api;
  final Future<String> Function() idTokenProvider;
  final ValueChanged<ProviderSignIn> onSignedIn;
  final VoidCallback onSwitchRole;

  /// Shown above the button, e.g. "Your session expired."
  final String? message;

  @override
  State<ProviderSignInScreen> createState() => _ProviderSignInScreenState();
}

class _ProviderSignInScreenState extends State<ProviderSignInScreen> {
  bool _busy = false;
  String? _error;

  /// "Continue with email" shows only when the server can send codes (accounts.email_login).
  bool _emailAvailable = false;

  @override
  void initState() {
    super.initState();
    widget.api.emailSignInEnabled().then((on) {
      if (mounted) setState(() => _emailAvailable = on);
    });
  }

  Future<void> _finishSignIn(ProviderSignIn result) async {
    await AuthStorage.save(access: result.tokens.access, refresh: result.tokens.refresh);
    unawaited(PushService.instance.register());
    if (mounted) widget.onSignedIn(result);
  }

  Future<void> _signInWithEmail() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => EmailSignInScreen(api: widget.api, role: 'provider')),
    );
    if (result == null || !mounted) return;
    await _finishSignIn(ProviderSignIn.fromJson(result));
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idToken = await widget.idTokenProvider();
      final result = await widget.api.signInProviderWithGoogle(idToken);
      await _finishSignIn(result);
    } on SignInCancelled {
      // They closed the Google sheet; nothing to report.
    } on SignInUnavailable catch (e) {
      _error = e.message;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not reach the server. Check your connection and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = _error ?? widget.message;
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const AppLogo()),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: AppColors.turquoise, shape: BoxShape.circle),
                child: const Icon(Icons.business_center_outlined, color: AppColors.white, size: 32),
              ),
              const SizedBox(height: 24),
              const Text(
                'Provider sign-in',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navy),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in with Google to register your business. We review every provider before '
                'they are matched with clients.',
                style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
              ),
              const SizedBox(height: 32),
              if (notice != null) ...[
                Text(
                  notice,
                  key: const Key('sign-in-message'),
                  style: TextStyle(fontSize: 13, color: _error != null ? const Color(0xFFBA1A1A) : AppColors.muted),
                ),
                const SizedBox(height: 14),
              ],
              BrandButton(
                label: 'Continue with Google',
                icon: Icons.login,
                busy: _busy,
                onPressed: _signIn,
              ),
              if (_emailAvailable) ...[
                const SizedBox(height: 12),
                BrandButton(
                  key: const Key('provider-email-sign-in'),
                  label: 'Continue with email',
                  icon: Icons.mail_outline,
                  outlined: true,
                  onPressed: _busy ? null : _signInWithEmail,
                ),
              ],
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : widget.onSwitchRole,
                  child: const Text('I need a service instead', style: TextStyle(color: AppColors.navy)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
