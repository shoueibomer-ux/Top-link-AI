import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/app_logo.dart';
import '../widgets/pressable.dart';
import 'device_id.dart';
import 'subscription_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, required this.onSubscribed});

  final VoidCallback onSubscribed;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _apiClient = ApiClient();
  late final _subscriptionService = SubscriptionService(apiClient: _apiClient);

  String? _deviceId;
  bool _isProcessing = false;
  String? _errorMessage;

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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // This screen's body is AppColors.lightBackground, not the
              // navy the wordmark's default white color assumes — see
              // AppLogo's class doc.
              const AppLogo(height: 36, wordmarkColor: AppColors.navy),
              const Spacer(),
              const Icon(Icons.workspace_premium, size: 64, color: AppColors.turquoise),
              const SizedBox(height: 24),
              const Text(
                'Unlock Top Link AI',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.navy),
              ),
              const SizedBox(height: 8),
              Text(
                'Subscribe to get matched with trusted local providers, powered by AI.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(kRadius),
                  boxShadow: kCardShadow,
                  border: Border.all(color: AppColors.turquoise, width: 2),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Monthly Plan',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.navy),
                    ),
                    const SizedBox(height: 8),
                    RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text: '\$9.99',
                            style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppColors.navy),
                          ),
                          TextSpan(
                            text: ' / month',
                            style: TextStyle(fontSize: 16, color: AppColors.navy),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _BenefitRow(text: 'Unlimited AI-powered matching'),
                    const _BenefitRow(text: 'Priority support'),
                    const _BenefitRow(text: 'Cancel anytime'),
                  ],
                ),
              ),
              const Spacer(),
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
                    onPressed: (_isProcessing || _deviceId == null) ? null : _subscribe,
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
                        : const Text('Subscribe', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isProcessing ? null : _restore,
                child: const Text('Restore purchases', style: TextStyle(color: AppColors.turquoise)),
              ),
            ],
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
