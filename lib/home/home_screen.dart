import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/service_request.dart';
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
import '../widgets/category_search_view.dart';
import '../widgets/notification_bell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.category,
    required this.urgency,
  });

  final ServiceCategory category;
  final Urgency urgency;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  /// A category confirmed from the search bar's detail page starts a new
  /// request in it, at the urgency step — the same flow "change category"
  /// starts, minus the category picking.
  void _startRequestIn(ServiceCategory category) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => OnboardingScreen(initialCategory: category)),
    );
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
          // The search field is pinned directly under the app bar: it sits
          // outside the scrolling list, and only on this tab.
          _ => CategorySearchView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              onSelect: _startRequestIn,
              child: _HomeTab(category: widget.category, urgency: widget.urgency),
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
  const _HomeTab({required this.category, required this.urgency});

  final ServiceCategory category;
  final Urgency urgency;

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Less at the top than the sides: the pinned search field above already
      // provides the breathing room (and a band of clear space under it that
      // the list scrolls beneath).
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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
          "We've got your ${category.label.toLowerCase()} request — a real person will reach out, usually by phone or text.",
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const SizedBox(height: 28),
        _RequestSummaryCard(category: category, urgency: urgency),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: kCardShadow,
          ),
          child: Row(
            children: [
              Icon(Icons.phone_forwarded_outlined, color: AppColors.turquoise),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  "We'll be in touch soon. Check \"History\" for every request you've submitted.",
                  style: TextStyle(fontSize: 13, color: AppColors.navy.withValues(alpha: 0.8)),
                ),
              ),
            ],
          ),
        ),
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
  Future<List<ServiceRequestRecord>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = _fetchRequests();
    });
  }

  Future<List<ServiceRequestRecord>> _fetchRequests() async {
    final deviceId = await getDeviceId();
    return _apiClient.getMyServiceRequests(deviceId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ServiceRequestRecord>>(
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

        final requests = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Your requests',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.navy),
            ),
            const SizedBox(height: 8),
            Text(
              "Every request you've submitted — we'll reach out by phone or text.",
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            if (requests.isEmpty)
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
                      "No requests yet — once you submit one, it'll show up here.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                  ],
                ),
              )
            else
              for (final request in requests) ...[
                ServiceRequestCard(request: request),
                const SizedBox(height: 14),
              ],
          ],
        );
      },
    );
  }
}

/// Public (not `_`-prefixed) so it can be pumped directly in widget tests
/// with a hand-built [ServiceRequestRecord] rather than needing to mock the
/// network call _HistoryTabState makes to fetch real data.
class ServiceRequestCard extends StatelessWidget {
  const ServiceRequestCard({super.key, required this.request});

  final ServiceRequestRecord request;

  @override
  Widget build(BuildContext context) {
    final category = findCategoryBySlug(request.category);
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
            child: Icon(category?.icon ?? Icons.assignment_outlined, color: AppColors.turquoise, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category?.label ?? request.category,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.phone_outlined, size: 13, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Text(request.phone, style: TextStyle(fontSize: 13, color: AppColors.muted)),
                  ],
                ),
                if (request.problemDescription.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    request.problemDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.muted, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
        ],
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
