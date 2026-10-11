import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/provider_profile.dart';
import '../app_colors.dart';
import '../role/app_role.dart';
import 'auth_storage.dart';
import 'google_sign_in_service.dart';
import 'provider_home_screen.dart';
import 'provider_pending_screen.dart';
import 'provider_registration_screen.dart';
import 'provider_session.dart';
import 'provider_sign_in_screen.dart';

enum _Stage { loading, signIn, register, edit, pending, home, error }

/// The provider side of the app: works out where the provider is in the
/// journey and shows that screen.
///
///   not signed in -> Google sign-in
///   signed in, no profile -> registration form
///   profile pending or rejected -> "Pending review"
///   profile approved -> provider home (with edit)
class ProviderGate extends StatefulWidget {
  const ProviderGate({super.key, this.api, this.idTokenProvider});

  final ApiClient? api;

  /// Where the Google ID token comes from; tests pass a fake.
  final Future<String> Function()? idTokenProvider;

  @override
  State<ProviderGate> createState() => _ProviderGateState();
}

class _ProviderGateState extends State<ProviderGate> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late final ProviderSession _session = ProviderSession(api: _api);

  _Stage _stage = _Stage.loading;
  ProviderProfileData? _profile;
  String _email = '';
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _stage = _Stage.loading);
    try {
      if (!await AuthStorage.isLoggedIn()) {
        _go(_Stage.signIn);
        return;
      }
      final profile = await _session.authorized(_api.getMyProviderProfile);
      if (profile == null) await _rememberEmail();
      _show(profile);
    } on SessionExpiredException {
      _go(_Stage.signIn, message: 'Your session expired. Please sign in again.');
    } on ApiException catch (e) {
      _go(_Stage.error, message: e.message);
    } catch (_) {
      _go(_Stage.error, message: 'Could not reach the server. Check your connection and try again.');
    }
  }

  /// A new registration starts with their Google email filled in.
  Future<void> _rememberEmail() async {
    try {
      final me = await _session.authorized(_api.getMe);
      _email = me.email;
    } catch (_) {
      // The form just starts with an empty email.
    }
  }

  void _go(_Stage stage, {String? message}) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _message = message;
    });
  }

  void _show(ProviderProfileData? profile) {
    _profile = profile;
    if (profile == null) {
      _go(_Stage.register);
    } else {
      _go(profile.status == ProviderStatus.approved ? _Stage.home : _Stage.pending);
    }
  }

  Future<void> _signOut() async {
    await AuthStorage.clear();
    await GoogleSignInService.signOut();
    _profile = null;
    _go(_Stage.signIn);
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.loading:
        return const Scaffold(
          backgroundColor: AppColors.lightBackground,
          body: Center(child: CircularProgressIndicator(color: AppColors.turquoise)),
        );
      case _Stage.signIn:
        return ProviderSignInScreen(
          api: _api,
          idTokenProvider: widget.idTokenProvider ?? GoogleSignInService.getIdToken,
          message: _message,
          onSwitchRole: () => switchRole(context),
          onSignedIn: (result) {
            _email = result.email;
            _show(result.profile);
          },
        );
      case _Stage.register:
      case _Stage.edit:
        return ProviderRegistrationScreen(
          key: ValueKey(_stage),
          session: _session,
          initial: _stage == _Stage.edit ? _profile : null,
          defaultEmail: _email,
          onCancel: _stage == _Stage.edit ? () => _show(_profile) : null,
          onSaved: _show,
          onSessionExpired: () => _go(_Stage.signIn, message: 'Your session expired. Please sign in again.'),
        );
      case _Stage.pending:
        return ProviderPendingScreen(
          profile: _profile!,
          onRefresh: _refresh,
          onEdit: () => _go(_Stage.edit),
          onSignOut: _signOut,
          onSwitchRole: () => switchRole(context),
        );
      case _Stage.home:
        return ProviderHomeScreen(
          profile: _profile!,
          onEdit: () => _go(_Stage.edit),
          onRefresh: _refresh,
          onSignOut: _signOut,
          onSwitchRole: () => switchRole(context),
        );
      case _Stage.error:
        return Scaffold(
          backgroundColor: AppColors.lightBackground,
          appBar: AppBar(title: const Text('Top-Link AI')),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.navy),
                const SizedBox(height: 16),
                Text(_message ?? 'Something went wrong.', textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: AppColors.navy)),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: _load, child: const Text('Try again')),
                TextButton(onPressed: _signOut, child: const Text('Sign out')),
              ],
            ),
          ),
        );
    }
  }

  /// "Check status": re-reads the profile without flashing the loading screen.
  Future<void> _refresh() async {
    try {
      _show(await _session.authorized(_api.getMyProviderProfile));
    } on SessionExpiredException {
      _go(_Stage.signIn, message: 'Your session expired. Please sign in again.');
    } catch (_) {
      // Keep showing what we have; the next refresh will try again.
    }
  }
}
