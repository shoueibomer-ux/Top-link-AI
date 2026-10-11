import 'package:flutter/material.dart';

import 'api/api_config.dart';
import 'app_colors.dart';
import 'role/root_gate.dart';
import 'onboarding/service_category.dart';

void main() {
  // A release build with an unsafe or missing API config (no HTTPS URL, or
  // the dev API key) must fail loudly here, not silently on every request.
  try {
    ApiConfig.validate();
  } on ApiConfigException catch (e) {
    runApp(ConfigErrorApp(message: e.message));
    return;
  }

  // Fire-and-forget: populates the dynamic category/service catalog as
  // early as possible so the category picker, provider profile, and
  // notification/history lookups all see it without each needing their own
  // loading state. Leaves the static fallback in place until this resolves.
  loadCatalogFromApi();
  runApp(const TopLinkApp());
}

class TopLinkApp extends StatelessWidget {
  const TopLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Top-Link AI',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.lightBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.turquoise,
          primary: AppColors.turquoise,
          secondary: AppColors.navy,
          surface: AppColors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.navy,
          foregroundColor: AppColors.white,
        ),
      ),
      home: const RootGate(),
    );
  }
}

/// Shown instead of the app when [ApiConfig.validate] rejects the build's
/// configuration. Aimed at whoever produced the build (a tester or release
/// engineer), so it is plain about what to fix.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Top-Link AI',
      home: Scaffold(
        backgroundColor: AppColors.lightBackground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.gpp_maybe_outlined, size: 48, color: AppColors.navy),
                const SizedBox(height: 16),
                const Text(
                  'This build is misconfigured',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.navy),
                ),
                const SizedBox(height: 12),
                Text(message, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.navy)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
