import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../api/api_client.dart';

/// Placeholder product ID — swap in the real App Store Connect / Play
/// Console product ID once developer accounts are set up. Until then,
/// [SubscriptionService.queryMonthlyProduct] always returns null (no such
/// product exists in any store yet), which is expected during development.
const monthlySubscriptionProductId = 'toplinkai_monthly_sub';

/// Placeholder ID for the paywall's "$4.99 one-time" option — a CONSUMABLE
/// (unlike the non-consumable subscription): a device can buy it again and
/// again, each purchase granting one single-use provider unlock. Same
/// caveat as [monthlySubscriptionProductId]: no such product exists in any
/// store yet.
const oneTimeUnlockProductId = 'toplinkai_unlock_one_time';

/// What a completed store purchase grants on our backend.
enum PurchaseKind { subscription, oneTimeUnlock }

/// Which grant a purchased [productId] maps to. Anything that isn't the
/// one-time product is the subscription — the only other thing sold.
PurchaseKind purchaseKindFor(String productId) =>
    productId == oneTimeUnlockProductId ? PurchaseKind.oneTimeUnlock : PurchaseKind.subscription;

/// Wraps the `in_app_purchase` plumbing for the paywall's two products: the
/// monthly plan and the one-time unlock.
///
/// None of this has been exercised against a real store listing — there's
/// no App Store/Play Store developer account configured yet. It's wired up
/// so that once a real product exists, [queryMonthlyProduct] /
/// [queryOneTimeUnlockProduct] will start returning it and the real purchase
/// path (`buy*` + [listenToPurchaseUpdates]) takes over automatically; until
/// then, callers fall back to the `simulate…ForDevelopment` methods to
/// exercise the paywall gate end-to-end.
class SubscriptionService {
  SubscriptionService({required this.apiClient});

  final ApiClient apiClient;
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  Future<bool> get isStoreAvailable => _iap.isAvailable();

  Future<ProductDetails?> queryMonthlyProduct() => _queryProduct(monthlySubscriptionProductId);

  Future<ProductDetails?> queryOneTimeUnlockProduct() => _queryProduct(oneTimeUnlockProductId);

  Future<ProductDetails?> _queryProduct(String productId) async {
    if (!await _iap.isAvailable()) return null;
    final response = await _iap.queryProductDetails({productId});
    if (response.error != null || response.productDetails.isEmpty) return null;
    return response.productDetails.first;
  }

  /// Starts the real store purchase flow for the subscription. Completion
  /// arrives asynchronously via the purchase stream — see
  /// [listenToPurchaseUpdates].
  Future<void> buy(ProductDetails product) {
    return _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
  }

  /// Starts the real store purchase flow for one single-use unlock. A
  /// consumable, so the store lets the same customer buy it again once it's
  /// been completed. Completion arrives via the purchase stream, like [buy].
  Future<void> buyOneTimeUnlock(ProductDetails product) {
    return _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: product));
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
            try {
              await _fulfil(purchase, deviceId);
            } catch (_) {
              // Deliberately NOT completing the purchase: the store keeps it
              // pending and redelivers it (with the same purchaseID, which
              // the backend treats idempotently) next launch, instead of the
              // customer having paid for something we never granted.
              onError('Your purchase went through but we could not record it yet. Please try again.');
              continue;
            }
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

  Future<void> _fulfil(PurchaseDetails purchase, String deviceId) {
    return switch (purchaseKindFor(purchase.productID)) {
      PurchaseKind.subscription => _activate(deviceId),
      PurchaseKind.oneTimeUnlock => apiClient.activateUnlockCredit(
          deviceId: deviceId,
          transactionId: purchase.purchaseID,
        ),
    };
  }

  /// TEMPORARY: activates a subscription directly against our backend with
  /// no store receipt behind it. Only reachable while [queryMonthlyProduct]
  /// returns null (no real product configured). Delete this once App
  /// Store/Play Store products exist and `buy` is the only activation path.
  Future<void> simulatePurchaseForDevelopment(String deviceId) => _activate(deviceId);

  /// TEMPORARY: grants a one-time unlock credit with no store purchase behind
  /// it. Only reachable while [queryOneTimeUnlockProduct] returns null. The
  /// timestamp id keeps repeated dev taps from being deduplicated into one
  /// credit. Delete once real products exist.
  Future<void> simulateOneTimePurchaseForDevelopment(String deviceId) {
    return apiClient.activateUnlockCredit(
      deviceId: deviceId,
      transactionId: 'dev-${DateTime.now().microsecondsSinceEpoch}',
    );
  }

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
