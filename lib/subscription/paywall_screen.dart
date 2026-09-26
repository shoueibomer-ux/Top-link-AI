import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/app_logo.dart';
import '../widgets/pressable.dart';
import 'device_id.dart';
import 'subscription_service.dart';

/// The app's up-front paywall (see subscription.AppEntryPoint) — two ways
/// past it, matching provider_search.models.ProviderMatch.UNLOCK_METHOD_CHOICES
/// one level up:
///   - $9.99/month subscription (existing) — unlimited provider unlocks
///     while active, same as ProviderUnlockView granting access for free
///     whenever `_is_subscribed(device_id)` is true.
///   - $4.99 one-time (new) — a single-unlock credit. UI/pricing only for
///     now; the purchase itself isn't wired up yet (see _buyOneTime) pending
///     confirming how a credit bought here — before any provider has even
///     been searched for — gets redeemed against the *next* provider this
///     device unlocks.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, required this.onSubscribed});

  final VoidCallback onSubscribed;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

/// The two ways a device can get past this screen — see the class doc on
/// [PaywallScreen] for which fields on the backend this maps to.
enum _PlanOption { subscription, oneTime }

class _PaywallScreenState extends State<PaywallScreen> {
  final _apiClient = ApiClient();
  late final _subscriptionService = SubscriptionService(apiClient: _apiClient);

  String? _deviceId;
  bool _isProcessing = false;
  String? _errorMessage;
  _PlanOption _selectedPlan = _PlanOption.subscription;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final deviceId = await getDeviceId();
    if (!mounted) return;
    setState(() => _deviceId = deviceId);
    _subscriptionService.listenToPurchaseUpdates(
      deviceId: deviceId,
      onActivated: () {
        if (mounted) widget.onSubscribed();
      },
      onError: (message) {
        if (mounted) setState(() => _errorMessage = message);
      },
    );
  }

  @override
  void dispose() {
    _subscriptionService.dispose();
    super.dispose();
  }

  Future<void> _subscribe() async {
    final deviceId = _deviceId;
    if (deviceId == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Bounded wait: an unreachable/misconfigured store (e.g. no Play Store
      // session on an emulator) must fall back to the dev path rather than
      // hang the paywall indefinitely.
      final product = await _subscriptionService
          .queryMonthlyProduct()
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (product != null) {
        // Real store product configured — the purchase stream listener set
        // up in _init() handles completion and calls onSubscribed().
        await _subscriptionService.buy(product);
      } else {
        // No real App Store/Play Store product exists yet (expected during
        // development) — activate directly so the gate is testable
        // end-to-end. Remove once real products are configured.
        await _subscriptionService.simulatePurchaseForDevelopment(deviceId);
        if (!mounted) return;
        widget.onSubscribed();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Could not complete purchase: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Deliberately not calling into SubscriptionService or the backend yet —
  // see PaywallScreen's class doc. Same "acknowledged, not yet functional"
  // shape as _restore() below rather than silently faking a purchase.
  void _buyOneTime() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('One-time unlock purchases are coming soon.')),
    );
  }

  void _restore() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No previous purchases to restore yet.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: SafeArea(
        // A scroll view (not the previous fixed Spacer-based layout) since
        // a second plan card means this no longer reliably fits one screen
        // on smaller devices.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              const AppLogo(height: 36),
              const SizedBox(height: 32),
              const Icon(Icons.workspace_premium, size: 64, color: AppColors.turquoise),
              const SizedBox(height: 24),
              const Text(
                'Unlock Top-Link AI',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.navy),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how you want to get matched with trusted local providers, powered by AI.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 28),
              _PlanCard(
                selected: _selectedPlan == _PlanOption.subscription,
                onTap: () => setState(() => _selectedPlan = _PlanOption.subscription),
                title: 'Monthly Plan',
                priceWhole: '\$9.99',
                priceSuffix: ' / month',
                benefits: const [
                  'Unlimited AI-powered matching',
                  'Priority support',
                  'Cancel anytime',
                ],
              ),
              const SizedBox(height: 14),
              _PlanCard(
                selected: _selectedPlan == _PlanOption.oneTime,
                onTap: () => setState(() => _selectedPlan = _PlanOption.oneTime),
                title: 'One-Time Unlock',
                priceWhole: '\$4.99',
                priceSuffix: ' one-time',
                benefits: const [
                  'Full contact details for one provider',
                  'No subscription, no recurring charge',
                ],
              ),
              const SizedBox(height: 28),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              Pressable(
                enabled: !_isProcessing && _deviceId != null,
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: (_isProcessing || _deviceId == null)
                        ? null
                        : (_selectedPlan == _PlanOption.subscription ? _subscribe : _buyOneTime),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.turquoise,
                      disabledBackgroundColor: AppColors.turquoise.withValues(alpha: 0.35),
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(AppColors.white),
                            ),
                          )
                        : Text(
                            _selectedPlan == _PlanOption.subscription
                                ? 'Subscribe'
                                : 'Unlock one provider — \$4.99',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isProcessing ? null : _restore,
                child: const Text('Restore purchases', style: TextStyle(color: AppColors.turquoise)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable plan — a tappable card with a radio-style indicator, the
/// same visual weight regardless of which option it represents (a customer
/// choosing the cheaper one-time unlock shouldn't feel steered away from
/// it).
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.selected,
    required this.onTap,
    required this.title,
    required this.priceWhole,
    required this.priceSuffix,
    required this.benefits,
  });

  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String priceWhole;
  final String priceSuffix;
  final List<String> benefits;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kRadius),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(kRadius),
              boxShadow: kCardShadow,
              border: Border.all(
                color: selected ? AppColors.turquoise : AppColors.cardBorder,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? AppColors.turquoise : AppColors.muted,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy),
                      ),
                      const SizedBox(height: 6),
                      // Text.rich (not a bare RichText) so this is still a
                      // Text widget under the hood — find.text() in tests
                      // can only see a RichText's flattened content that way.
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: priceWhole,
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.navy),
                            ),
                            TextSpan(
                              text: priceSuffix,
                              style: const TextStyle(fontSize: 14, color: AppColors.navy),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final benefit in benefits) _BenefitRow(text: benefit),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: AppColors.turquoise),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 14, color: AppColors.navy)),
        ],
      ),
    );
  }
}
