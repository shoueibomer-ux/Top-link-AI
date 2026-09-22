import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/provider_match.dart';
import '../api/real_provider.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../chat/chat_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/service_category.dart';
import '../onboarding/urgency_step.dart';
import '../pages/settings_page.dart';
import '../subscription/device_id.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_logo.dart';
import '../widgets/notification_bell.dart';
import '../widgets/real_provider_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.category,
    required this.urgency,
    required this.providers,
  });

  final ServiceCategory category;
  final Urgency urgency;
  final List<RealProvider> providers;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  // Local, mutable copy so "not interested" can remove a card from view
  // without needing a backend round-trip.
  late final List<RealProvider> _providers = List.of(widget.providers);

  void _dismiss(RealProvider provider) {
    setState(() => _providers.remove(provider));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const AppLogo(),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: NotificationBell(),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: switch (_tabIndex) {
          1 => const _HistoryTab(),
          2 => const ChatScreen(),
          3 => const SettingsBody(),
          _ => _HomeTab(
              category: widget.category,
              urgency: widget.urgency,
              providers: _providers,
              onDismiss: _dismiss,
            ),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.turquoise.withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: AppColors.navy),
            selectedIcon: Icon(Icons.home_outlined, color: AppColors.turquoise),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined, color: AppColors.navy),
            selectedIcon: Icon(Icons.history_outlined, color: AppColors.turquoise),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline, color: AppColors.navy),
            selectedIcon: Icon(Icons.chat_bubble_outline, color: AppColors.turquoise),
            label: 'Ask AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, color: AppColors.navy),
            selectedIcon: Icon(Icons.person_outline, color: AppColors.turquoise),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.category,
    required this.urgency,
    required this.providers,
    required this.onDismiss,
  });

  final ServiceCategory category;
  final Urgency urgency;
  final List<RealProvider> providers;
  final ValueChanged<RealProvider> onDismiss;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          "You're all set!",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "We're matching you with top ${category.label.toLowerCase()} providers in your area.",
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const SizedBox(height: 28),
        _RequestSummaryCard(category: category, urgency: urgency),
        const SizedBox(height: 32),
        const Text(
          'Recommended providers',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 14),
        if (providers.isEmpty)
          const _EmptyProvidersNotice()
        else
          for (final provider in providers) ...[
            RealProviderCard(provider: provider, category: category.slug, onDismiss: () => onDismiss(provider)),
            const SizedBox(height: 14),
          ],
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              );
            },
            child: const Text(
              'Start a new request',
              style: TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

/// Request status pipeline: every provider this device has unlocked, each
/// carrying a status (see ProviderMatchStatus) the client can advance
/// manually. Status lives on the backend (ProviderMatch.status), so this
/// re-fetches on every mount rather than caching locally — switching away to
/// another tab and back always reflects what's actually persisted.
class _HistoryTab extends StatefulWidget {
  const _HistoryTab();

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  final _apiClient = ApiClient();
  String _filter = 'all';
  Future<List<ProviderMatchRecord>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = _fetchMatches();
    });
  }

  Future<List<ProviderMatchRecord>> _fetchMatches() async {
    final deviceId = await getDeviceId();
    return _apiClient.getProviderMatches(deviceId);
  }

  Future<void> _updateStatus(ProviderMatchRecord match, String status) async {
    try {
      final deviceId = await getDeviceId();
      await _apiClient.updateProviderMatchStatus(deviceId: deviceId, matchId: match.id, status: status);
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update status — try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProviderMatchRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: AppColors.turquoise));
        }
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(kRadius),
                  boxShadow: kCardShadow,
                ),
                child: Column(
                  children: [
                    Text(
                      'Could not load your requests right now.',
                      style: TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Retry', style: TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final matches = snapshot.data!;
        final counts = <String, int>{for (final status in ProviderMatchStatus.all) status: 0};
        for (final match in matches) {
          counts[match.status] = (counts[match.status] ?? 0) + 1;
        }
        final visible = _filter == 'all' ? matches : matches.where((m) => m.status == _filter).toList();

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Your requests',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.navy),
            ),
            const SizedBox(height: 8),
            Text(
              "Track every provider you've matched with, from first contact to done.",
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _StatusChip(
                    label: 'All',
                    count: matches.length,
                    selected: _filter == 'all',
                    onTap: () => setState(() => _filter = 'all'),
                  ),
                  for (final status in ProviderMatchStatus.all) ...[
                    const SizedBox(width: 8),
                    _StatusChip(
                      label: ProviderMatchStatus.label(status),
                      count: counts[status] ?? 0,
                      selected: _filter == status,
                      onTap: () => setState(() => _filter = status),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (visible.isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(kRadius),
                  boxShadow: kCardShadow,
                ),
                child: Column(
                  children: [
                    Icon(Icons.history_outlined, size: 36, color: AppColors.muted),
                    const SizedBox(height: 12),
                    Text(
                      matches.isEmpty
                          ? "No requests yet — once you match with a provider, it'll show up here."
                          : 'No requests with this status.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                  ],
                ),
              )
            else
              for (final match in visible) ...[
                _RequestCard(match: match, onStatusSelected: (status) => _updateStatus(match, status)),
                const SizedBox(height: 14),
              ],
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.turquoise : AppColors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: selected ? null : kCardShadow,
          ),
          child: Text(
            '$label ($count)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.white : AppColors.navy,
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.match, required this.onStatusSelected});

  final ProviderMatchRecord match;
  final ValueChanged<String> onStatusSelected;

  @override
  Widget build(BuildContext context) {
    final category = findCategoryBySlug(match.category);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.turquoise.withValues(alpha: 0.12),
            child: Icon(category?.icon ?? Icons.storefront, color: AppColors.turquoise, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.providerName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy),
                ),
                const SizedBox(height: 3),
                Text(category?.label ?? match.category, style: TextStyle(fontSize: 13, color: AppColors.muted)),
                if (match.problemDescription.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    match.problemDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.muted, fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 10),
                _StatusBadge(status: match.status),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Update status',
            icon: Icon(Icons.more_vert, color: AppColors.muted, size: 20),
            onSelected: onStatusSelected,
            itemBuilder: (context) => [
              for (final status in ProviderMatchStatus.all)
                PopupMenuItem(value: status, child: Text(ProviderMatchStatus.label(status))),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ProviderMatchStatus.archived || ProviderMatchStatus.cancelled => AppColors.muted,
      ProviderMatchStatus.completed => AppColors.navy,
      _ => AppColors.turquoise,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        ProviderMatchStatus.label(status),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _RequestSummaryCard extends StatelessWidget {
  const _RequestSummaryCard({required this.category, required this.urgency});

  final ServiceCategory category;
  final Urgency urgency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Row(
        children: [
          _IconBadge(icon: category.icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(urgency.icon, size: 14, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Text(
                      urgency.label,
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.turquoise.withValues(alpha: 0.12),
      child: Icon(icon, color: AppColors.turquoise),
    );
  }
}

class _EmptyProvidersNotice extends StatelessWidget {
  const _EmptyProvidersNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Text(
        "No providers found nearby yet — we'll notify you as soon as one is available.",
        style: TextStyle(fontSize: 14, color: AppColors.muted),
      ),
    );
  }
}
