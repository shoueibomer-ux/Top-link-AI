import 'package:flutter/material.dart';

import 'dart:async';

import '../api/api_client.dart';
import '../messaging/push_service.dart';
import '../app_colors.dart';
import '../provider/auth_storage.dart';
import '../provider/google_sign_in_service.dart';
import '../provider/provider_widgets.dart';
import '../widgets/app_logo.dart';

/// Asks the client to sign in with Google, then closes with `true`. Shown when
/// they submit a request (or open their history) without being signed in: a
/// request belongs to the account that sent it, which is also what lets them
/// chat with providers and review a job later. "Not now" closes with `false`
/// and nothing is sent.
class ClientSignInScreen extends StatefulWidget {
  const ClientSignInScreen({
    super.key,
    required this.api,
    this.idTokenProvider,
    this.title = 'Sign in to send your request',
    this.message =
        'We use your Google account so your request, the replies and your job history stay yours. '
        'Your request is sent as soon as you sign in.',
  });

  final ApiClient api;

  /// Where the Google ID token comes from; tests pass a fake.
  final Future<String> Function()? idTokenProvider;
  final String title;
  final String message;

  @override
  State<ClientSignInScreen> createState() => _ClientSignInScreenState();
}

class _ClientSignInScreenState extends State<ClientSignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idToken = await (widget.idTokenProvider ?? GoogleSignInService.getIdToken)();
      final result = await widget.api.signInClientWithGoogle(idToken);
      await AuthStorage.save(access: result.tokens.access, refresh: result.tokens.refresh);
      unawaited(PushService.instance.register());
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    } on SignInCancelled {
      // They closed the Google sheet; nothing to report.
    } on SignInUnavailable catch (e) {
      _error = e.message;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not reach the server. Check your connection and try again.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
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
                child: const Icon(Icons.person_outline, color: AppColors.white, size: 32),
              ),
              const SizedBox(height: 24),
              Text(
                widget.title,
                key: const Key('client-sign-in-title'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navy),
              ),
              const SizedBox(height: 8),
              Text(widget.message, style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted)),
              const SizedBox(height: 32),
              if (_error != null) ...[
                Text(
                  _error!,
                  key: const Key('client-sign-in-error'),
                  style: const TextStyle(fontSize: 13, color: Color(0xFFBA1A1A)),
                ),
                const SizedBox(height: 14),
              ],
              BrandButton(
                key: const Key('client-google-sign-in'),
                label: 'Continue with Google',
                icon: Icons.login,
                busy: _busy,
                onPressed: _signIn,
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  key: const Key('client-sign-in-not-now'),
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Not now', style: TextStyle(color: AppColors.navy)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
