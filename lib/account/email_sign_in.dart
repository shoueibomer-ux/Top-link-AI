import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../app_colors.dart';
import '../provider/provider_widgets.dart';
import '../widgets/app_logo.dart';

/// "Continue with email": the person types their email, gets a 6-digit code, and types it here. No password.
/// Closes with the server's sign-in answer (same shape as the Google sign-in for [role]: parse it with
/// ClientSignIn.fromJson or ProviderSignIn.fromJson), or null if they back out. See accounts.email_login.
class EmailSignInScreen extends StatefulWidget {
  const EmailSignInScreen({super.key, required this.api, required this.role});

  final ApiClient api;

  /// 'customer' or 'provider'.
  final String role;

  @override
  State<EmailSignInScreen> createState() => _EmailSignInScreenState();
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class _EmailSignInScreenState extends State<EmailSignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _email.addListener(() => setState(() {}));
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _cleanEmail => _email.text.trim().toLowerCase();

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not reach the server. Check your connection and try again.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _sendCode() => _run(() async {
        final message = await widget.api.startEmailSignIn(_cleanEmail, widget.role);
        _codeSent = true;
        _info = message;
        _code.clear();
      });

  Future<void> _verify() => _run(() async {
        final result = await widget.api.verifyEmailSignIn(_cleanEmail, widget.role, _code.text.trim());
        if (mounted) Navigator.of(context).pop(result);
      });

  @override
  Widget build(BuildContext context) {
    final canSend = !_busy && _emailPattern.hasMatch(_email.text.trim());
    final canVerify = !_busy && RegExp(r'^\d{6}$').hasMatch(_code.text.trim());
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const AppLogo()),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Continue with email',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navy),
            ),
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? 'Enter the 6-digit code we emailed to $_cleanEmail.'
                  : "We'll email you a 6-digit code. No password needed.",
              style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            TextField(
              key: const Key('email-sign-in-email'),
              controller: _email,
              enabled: !_codeSent && !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              onSubmitted: (_) => canSend ? _sendCode() : null,
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              TextField(
                key: const Key('email-sign-in-code'),
                controller: _code,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                decoration: const InputDecoration(labelText: '6-digit code', border: OutlineInputBorder()),
                onSubmitted: (_) => canVerify ? _verify() : null,
              ),
            ],
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, key: const Key('email-sign-in-error'), style: const TextStyle(fontSize: 13, color: Color(0xFFBA1A1A))),
              const SizedBox(height: 12),
            ] else if (_info != null) ...[
              Text(_info!, key: const Key('email-sign-in-info'), style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(height: 12),
            ],
            if (!_codeSent)
              BrandButton(
                key: const Key('email-sign-in-send'),
                label: 'Send code',
                icon: Icons.mail_outline,
                busy: _busy,
                onPressed: canSend ? _sendCode : null,
              )
            else ...[
              BrandButton(
                key: const Key('email-sign-in-verify'),
                label: 'Sign in',
                icon: Icons.login,
                busy: _busy,
                onPressed: canVerify ? _verify : null,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    key: const Key('email-sign-in-change'),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _info = null;
                              _error = null;
                            }),
                    child: const Text('Use a different email', style: TextStyle(color: AppColors.navy)),
                  ),
                  TextButton(
                    key: const Key('email-sign-in-resend'),
                    onPressed: _busy ? null : _sendCode,
                    child: const Text('Send a new code', style: TextStyle(color: AppColors.turquoise)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
