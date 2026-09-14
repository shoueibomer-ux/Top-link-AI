import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../api/api_client.dart';

/// Placeholder product ID — swap in the real App Store Connect / Play
/// Console product ID once developer accounts are set up. Until then,
/// [queryMonthlyProduct] always returns null (no such product exists in any
/// store yet), which is expected during development.
const monthlySubscriptionProductId = 'toplinkai_monthly_sub';

/// Wraps the `in_app_purchase` plumbing for the single monthly plan.
///
/// None of this has been exercised against a real store listing — there's
/// no App Store/Play Store developer account configured yet. It's wired up
/// so that once a real product exists, [queryMonthlyProduct] will start
/// returning it and the real purchase path (`buy` + [listenToPurchaseUpdates])
/// takes over automatically; until then, callers fall back to
/// [simulatePurchaseForDevelopment] to exercise the paywall gate end-to-end.
class SubscriptionService {
  SubscriptionService({required this.apiClient});

  final ApiClient apiClient;
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  Future<bool> get isStoreAvailable => _iap.isAvailable();

  Future<ProductDetails?> queryMonthlyProduct() async {
    if (!await _iap.isAvailable()) return null;
    final response = await _iap.queryProductDetails({monthlySubscriptionProductId});
    if (response.error != null || response.productDetails.isEmpty) return null;
    return response.productDetails.first;
  }

  /// Starts the real store purchase flow. Completion arrives asynchronously
  /// via the purchase stream — see [listenToPurchaseUpdates].
  Future<void> buy(ProductDetails product) {
    return _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
  }

  void listenToPurchaseUpdates({
    required String deviceId,
    required void Function() onActivated,
    required void Function(String message) onError,
  }) {
    _purchaseSubscription = _iap.purchaseStream.listen((purchases) async {
      for (final purchase in purchases) {
        switch (purchase.status) {
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            await _activate(deviceId);
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
            onActivated();
          case PurchaseStatus.error:
            onError(purchase.error?.message ?? 'Purchase failed.');
          case PurchaseStatus.pending:
          case PurchaseStatus.canceled:
            break;
        }
      }
    });
  }

  void dispose() => _purchaseSubscription?.cancel();

  /// TEMPORARY: activates a subscription directly against our backend with
  /// no store receipt behind it. Only reachable while [queryMonthlyProduct]
  /// returns null (no real product configured). Delete this once App
  /// Store/Play Store products exist and `buy` is the only activation path.
  Future<void> simulatePurchaseForDevelopment(String deviceId) => _activate(deviceId);

  Future<void> _activate(String deviceId) {
    final now = DateTime.now();
    return apiClient.activateSubscription(
      deviceId: deviceId,
      status: 'active',
      startDate: now,
      expiryDate: now.add(const Duration(days: 30)),
    );
  }
}
