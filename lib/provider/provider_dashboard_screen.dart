import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_colors.dart';
import '../app_styles.dart';

/// A stand-in for a real provider dashboard. This app has no provider
/// login/signup system (see provider_search.models.ProviderAvailability's
/// docstring) — real businesses are sourced from Google Places, not signed
/// up accounts — so "signing in" here just means picking which already-found
/// business to toggle availability for. The toggle itself is fully real:
/// it reads/writes provider_search.models.ProviderAvailability and is what
/// drives the "Available now / Busy" badge on client-facing provider cards.
class ProviderDashboardScreen extends StatefulWidget {
  const ProviderDashboardScreen({super.key});

  @override
  State<ProviderDashboardScreen> createState() => _ProviderDashboardScreenState();
}

class _ProviderDashboardScreenState extends State<ProviderDashboardScreen> {
  final _apiClient = ApiClient();
  late Future<List<KnownProvider>> _providersFuture;

  KnownProvider? _selected;
  bool? _isAvailableNow;
  bool _loadingAvailability = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _providersFuture = _apiClient.getKnownProviders();
  }

  Future<void> _selectProvider(KnownProvider? provider) async {
    setState(() {
      _selected = provider;
      _isAvailableNow = null;
    });
    if (provider == null) return;

    setState(() => _loadingAvailability = true);
    try {
      final isAvailable = await _apiClient.getProviderAvailability(provider.placeId);
      if (mounted) setState(() => _isAvailableNow = isAvailable);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load availability — try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingAvailability = false);
    }
  }

  Future<void> _setAvailability(bool value) async {
    final provider = _selected;
    if (provider == null) return;

    setState(() {
      _isAvailableNow = value;
      _saving = true;
    });
    try {
      final confirmed = await _apiClient.setProviderAvailability(
        placeId: provider.placeId,
        isAvailableNow: value,
      );
      if (mounted) setState(() => _isAvailableNow = confirmed);
    } catch (_) {
      if (mounted) {
        setState(() => _isAvailableNow = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update availability — try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Provider Dashboard')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.turquoise.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(kRadius),
              ),
              child: Text(
                "Demo: this app doesn't have provider accounts yet, so pick which "
                "business you're signing in as below. The toggle itself is real — "
                "it's what clients see as \"Available now\" or \"Busy\" on that "
                "provider's card.",
                style: TextStyle(fontSize: 13, color: AppColors.navy.withValues(alpha: 0.8)),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Sign in as',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<KnownProvider>>(
              future: _providersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator(color: AppColors.turquoise)),
                  );
                }
                if (snapshot.hasError) {
                  return Text('Could not load providers.', style: TextStyle(color: AppColors.muted));
                }
                final providers = snapshot.data!;
                if (providers.isEmpty) {
                  return Text(
                    'No providers found yet — search for a category in the app first.',
                    style: TextStyle(color: AppColors.muted),
                  );
                }
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(kRadius),
                    boxShadow: kCardShadow,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<KnownProvider>(
                      isExpanded: true,
                      hint: const Text('Choose a business'),
                      value: _selected,
                      items: [
                        for (final provider in providers)
                          DropdownMenuItem(value: provider, child: Text(provider.name)),
                      ],
                      onChanged: _selectProvider,
                    ),
                  ),
                );
              },
            ),
            if (_selected != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(kRadius),
                  boxShadow: kCardShadow,
                ),
                child: _loadingAvailability || _isAvailableNow == null
                    ? const Center(child: CircularProgressIndicator(color: AppColors.turquoise))
                    : Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Available now',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _isAvailableNow!
                                      ? 'Clients see a green "Available now" badge on your card.'
                                      : 'Clients see a "Busy" badge on your card.',
                                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isAvailableNow!,
                            activeThumbColor: AppColors.turquoise,
                            onChanged: _saving ? null : _setAvailability,
                          ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
