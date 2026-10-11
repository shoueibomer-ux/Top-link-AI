import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../onboarding/onboarding_screen.dart';
import '../provider/provider_gate.dart';
import 'app_role.dart';
import 'role_choice_screen.dart';

/// The app's first screen. Sends the person to the side of the app they chose
/// last time (client request flow, or the provider flow), or asks them to
/// choose if they haven't yet.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  AppRole? _role;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    RoleStorage.load().then((role) {
      if (mounted) {
        setState(() {
          _role = role;
          _loaded = true;
        });
      }
    });
  }

  Future<void> _choose(AppRole role) async {
    await RoleStorage.save(role);
    if (mounted) setState(() => _role = role);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: AppColors.lightBackground,
        body: Center(child: CircularProgressIndicator(color: AppColors.turquoise)),
      );
    }
    return switch (_role) {
      AppRole.client => const OnboardingScreen(),
      AppRole.provider => const ProviderGate(),
      null => RoleChoiceScreen(onChosen: _choose),
    };
  }
}
