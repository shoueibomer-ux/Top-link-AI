import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/real_provider.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../subscription/device_id.dart';
import '../subscription/paywall_screen.dart';

/// The one flow behind every "Unlock contact — \$4.99 or subscribe" CTA
/// (see RealProviderCard / ProviderDetailsSheet). Tries the free path first
/// — a subscribed device's unlock always succeeds with no prompt — and only
/// asks the client to choose between paying \$4.99 or subscribing when the
/// backend actually says payment is required (provider_search.views.
/// ProviderUnlockView, HTTP 402). Returns the unlocked [RealProvider], or
/// null if the client backed out at any point.
Future<RealProvider?> showUnlockProviderDialog(
  BuildContext context, {
  required RealProvider provider,
  required String category,
}) async {
  final placeId = provider.placeId;
  final messenger = ScaffoldMessenger.of(context);
  if (placeId == null) {
    messenger.showSnackBar(const SnackBar(content: Text('This provider cannot be unlocked right now.')));
    return null;
  }

  final apiClient = ApiClient();
  final city = provider.city ?? ApiClient.demoCity;

  Future<RealProvider?> attempt({required bool paid}) async {
    final deviceId = await getDeviceId();
    try {
      return await apiClient.unlockProvider(
        deviceId: deviceId,
        placeId: placeId,
        category: category,
        city: city,
        paid: paid,
      );
    } on PaymentRequiredException {
      rethrow;
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return null;
    }
  }

  String priceUsd = '4.99';
  try {
    return await attempt(paid: false);
  } on PaymentRequiredException catch (e) {
    priceUsd = e.priceUsd;
  }

  if (!context.mounted) return null;
  final choice = await showModalBottomSheet<_UnlockChoice>(
    context: context,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(kCardRadius))),
    builder: (_) => _UnlockChoiceSheet(providerName: provider.name, priceUsd: priceUsd),
  );

  if (choice == _UnlockChoice.pay) {
    // No real consumable in-app-purchase product is configured yet (same
    // limitation as SubscriptionService.simulatePurchaseForDevelopment) —
    // `paid: true` here is what a completed $4.99 purchase would trigger.
    return attempt(paid: true);
  }
  if (choice == _UnlockChoice.subscribe) {
    if (!context.mounted) return null;
    final subscribed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (routeContext) => PaywallScreen(onSubscribed: () => Navigator.of(routeContext).pop(true)),
      ),
    );
    if (subscribed == true) return attempt(paid: false);
  }
  return null;
}

enum _UnlockChoice { pay, subscribe }

class _UnlockChoiceSheet extends StatelessWidget {
  const _UnlockChoiceSheet({required this.providerName, required this.priceUsd});

  final String providerName;
  final String priceUsd;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Unlock contact details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy),
            ),
            const SizedBox(height: 6),
            Text(
              "See $providerName's phone number and address.",
              style: const TextStyle(fontSize: 13, color: AppColors.mutedText),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_UnlockChoice.subscribe),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.turquoise,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                ),
                child: const Text('Subscribe for unlimited unlocks', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(_UnlockChoice.pay),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                ),
                child: Text('Unlock just this one — \$$priceUsd', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Not now', style: TextStyle(color: AppColors.mutedText)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
