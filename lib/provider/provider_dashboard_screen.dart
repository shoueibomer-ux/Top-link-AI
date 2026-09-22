import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/provider_match.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../onboarding/service_category.dart';
import 'auth_storage.dart';
import 'provider_auth_screen.dart';

/// The provider's home base: an "incoming requests" queue (real, requires a
/// logged-in provider account — see ProviderIncomingRequestListView) sits
/// above a legacy demo section. That demo section predates real provider
/// accounts (see provider_search.models.ProviderAvailability's docstring) —
/// "signing in" there just means picking which already-found business to
/// toggle availability for, no login required. It's left in place rather
/// than removed: the toggle itself is fully real (it drives the "Available
/// now / Busy" badge on client-facing provider cards) and nothing else in
/// the app replaces it yet.
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

  // --- Incoming requests (real, authenticated) ---
  String? _accessToken;
  bool _authChecked = false;
  Future<List<ProviderMatchRecord>>? _requestsFuture;

  @override
  void initState() {
    super.initState();
    _providersFuture = _apiClient.getKnownProviders();
    _loadAuthAndRequests();
  }

  Future<void> _loadAuthAndRequests() async {
    final token = await AuthStorage.getAccessToken();
    if (!mounted) return;
    setState(() {
      _accessToken = token;
      _authChecked = true;
    });
    if (token != null) _loadRequests();
  }

  void _loadRequests() {
    final token = _accessToken;
    if (token == null) return;
    setState(() => _requestsFuture = _apiClient.getIncomingProviderRequests(token));
  }

  Future<void> _goToLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProviderAuthScreen()),
    );
    if (mounted) _loadAuthAndRequests();
  }

  Future<void> _respond(ProviderMatchRecord request, String decision, String message) async {
    final token = _accessToken;
    if (token == null) return;
    try {
      await _apiClient.respondToProviderRequest(
        accessToken: token,
        requestId: request.id,
        decision: decision,
        message: message,
      );
      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision == ProviderDecision.accepted ? 'Request accepted.' : 'Request declined.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send your response — try again.')),
        );
      }
      rethrow;
    }
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
            const Text(
              'Incoming requests',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy),
            ),
            const SizedBox(height: 6),
            Text(
              "Clients who've unlocked your contact details, waiting on a reply.",
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            _IncomingRequestsSection(
              authChecked: _authChecked,
              accessToken: _accessToken,
              requestsFuture: _requestsFuture,
              onLogIn: _goToLogin,
              onRetry: _loadRequests,
              onRespond: _respond,
            ),
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 20),
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

/// The gate + content for the "Incoming requests" queue: a log-in prompt
/// when there's no provider account signed in yet, otherwise the real
/// FutureBuilder over ProviderIncomingRequestListView.
class _IncomingRequestsSection extends StatelessWidget {
  const _IncomingRequestsSection({
    required this.authChecked,
    required this.accessToken,
    required this.requestsFuture,
    required this.onLogIn,
    required this.onRetry,
    required this.onRespond,
  });

  final bool authChecked;
  final String? accessToken;
  final Future<List<ProviderMatchRecord>>? requestsFuture;
  final VoidCallback onLogIn;
  final VoidCallback onRetry;
  final Future<void> Function(ProviderMatchRecord request, String decision, String message) onRespond;

  @override
  Widget build(BuildContext context) {
    if (!authChecked) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: AppColors.turquoise)),
      );
    }

    if (accessToken == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(kRadius),
          boxShadow: kCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Log in to your business account to see and reply to real client requests.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onLogIn,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
              ),
              child: const Text('Log in', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<List<ProviderMatchRecord>>(
      future: requestsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: AppColors.turquoise)),
          );
        }
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(kRadius),
              boxShadow: kCardShadow,
            ),
            child: Column(
              children: [
                Text('Could not load your requests.', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry', style: TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          );
        }

        final requests = snapshot.data!;
        if (requests.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(kRadius),
              boxShadow: kCardShadow,
            ),
            child: Text(
              "No pending requests right now — you'll see new ones here as soon as a client unlocks your contact details.",
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          );
        }

        return Column(
          children: [
            for (final request in requests) ...[
              IncomingRequestCard(
                key: ValueKey(request.id),
                request: request,
                onRespond: (decision, message) => onRespond(request, decision, message),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

/// One pending request with an optional reply message and Accept/Decline
/// actions — owns its own TextEditingController and in-flight state so the
/// parent list doesn't need to track either per request.
/// Public (not `_`-prefixed) so it can be pumped directly in widget tests
/// with a hand-built [ProviderMatchRecord] and a stub `onRespond` — the same
/// pattern RealProviderCard uses — rather than needing to mock the network
/// call the real dashboard makes to fetch the queue itself.
class IncomingRequestCard extends StatefulWidget {
  const IncomingRequestCard({super.key, required this.request, required this.onRespond});

  final ProviderMatchRecord request;
  final Future<void> Function(String decision, String message) onRespond;

  @override
  State<IncomingRequestCard> createState() => _IncomingRequestCardState();
}

class _IncomingRequestCardState extends State<IncomingRequestCard> {
  final _messageController = TextEditingController();
  bool _responding = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _handle(String decision) async {
    setState(() => _responding = true);
    try {
      await widget.onRespond(decision, _messageController.text.trim());
      // No further setState after this — a successful respond causes the
      // parent to reload and this card to be removed from the tree.
    } catch (_) {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final categoryLabel = findCategoryBySlug(request.category)?.label ?? request.category;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.turquoise.withValues(alpha: 0.12),
                child: const Icon(Icons.assignment_outlined, color: AppColors.turquoise, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categoryLabel,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy),
                    ),
                    Text(request.city, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          if (request.problemDescription.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              request.problemDescription,
              style: TextStyle(fontSize: 13, color: AppColors.navy.withValues(alpha: 0.8)),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.lightBackground,
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: TextField(
              controller: _messageController,
              enabled: !_responding,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Optional reply message…',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _responding ? null : () => _handle(ProviderDecision.declined),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                  ),
                  child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _responding ? null : () => _handle(ProviderDecision.accepted),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.turquoise,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                  ),
                  child: _responding
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                        )
                      : const Text('Accept', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
