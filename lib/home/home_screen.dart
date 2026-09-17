import 'package:flutter/material.dart';

import '../api/real_provider.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/service_category.dart';
import '../onboarding/urgency_step.dart';
import '../pages/settings_page.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_logo.dart';
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
            child: _NotificationBell(),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: switch (_tabIndex) {
          1 => const _HistoryTab(),
          2 => const SettingsBody(),
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
            icon: Icon(Icons.person_outline, color: AppColors.navy),
            selectedIcon: Icon(Icons.person_outline, color: AppColors.turquoise),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      // No real notifications exist yet — the badge just signals the
      // feature is coming rather than reflecting an actual unread count.
      icon: const Badge(
        backgroundColor: AppColors.turquoise,
        smallSize: 9,
        child: Icon(Icons.notifications_outlined),
      ),
      color: AppColors.white,
      tooltip: 'Notifications',
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notifications are coming soon.')),
        );
      },
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
            RealProviderCard(provider: provider, onDismiss: () => onDismiss(provider)),
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

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Your request history',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Past requests and the providers you matched with will show up here.',
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const SizedBox(height: 28),
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
                "No past requests yet — once you complete a match, it'll show up here.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
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
