import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_colors.dart';
import '../onboarding/onboarding_screen.dart';
import 'device_id.dart';
import 'paywall_screen.dart';

/// Dev-only escape hatch: `flutter run --dart-define=SKIP_PAYWALL=true`
/// skips the subscription check entirely. Gated on [kDebugMode] on top of
/// the dart-define itself, so it's a no-op in profile/release builds even if
/// someone passed the flag by mistake — there is no way to ship a build that
/// bypasses the paywall.
const bool kSkipPaywall = bool.fromEnvironment('SKIP_PAYWALL');

/// The app's real starting point: gates the onboarding/matching flow behind
/// an active subscription. Shown on cold start and whenever the app needs
/// to re-check access (e.g. after "Log out" in Settings).
class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});

  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint> {
  late final Future<bool> _isSubscribedFuture = _checkSubscription();

  Future<bool> _checkSubscription() async {
    if (kDebugMode && kSkipPaywall) return true;
    final deviceId = await getDeviceId();
    try {
      final subscriptionStatus = await ApiClient().getSubscriptionStatus(deviceId);
      // An active subscription OR a bought one-time unlock — see
      // SubscriptionStatus.canEnterApp for why the latter must not be bounced
      // back to the paywall.
      return subscriptionStatus.canEnterApp;
    } catch (_) {
      // Can't reach the backend to verify — fail closed (show the paywall)
      // rather than silently granting access. A production build should
      // also cache the last verified status locally so a flaky network
      // doesn't lock out an already-subscribed user; that's not wired up
      // yet since there's no real billing to verify against either.
      return false;
    }
  }

  void _onSubscribed() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isSubscribedFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: AppColors.lightBackground,
            body: Center(child: CircularProgressIndicator(color: AppColors.turquoise)),
          );
        }
        if (snapshot.data!) {
          return const OnboardingScreen();
        }
        return PaywallScreen(onSubscribed: _onSubscribed);
      },
    );
  }
}
