import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/service_request.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../chat/chat_screen.dart';
import '../client/client_sign_in_screen.dart';
import '../messaging/conversation_screen.dart';
import '../messaging/push_service.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/service_category.dart';
import '../onboarding/urgency_step.dart';
import '../pages/settings_page.dart';
import '../provider/auth_storage.dart';
import '../provider/provider_session.dart';
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
          1 => const HistoryTab(),
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
          "We've got your ${category.label.toLowerCase()} request. Providers who can help will accept it, and you can message them from History.",
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
              Icon(Icons.chat_bubble_outline, color: AppColors.turquoise),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  "We'll notify you when a provider accepts. Open \"History\" to message them and to see every request you've submitted.",
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
/// "Your requests": everything this account has submitted, and who accepted it.
/// Needs a signed-in client; without one it offers to sign in instead of
/// showing anything. Public so tests can pump it with a fake backend.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key, this.api, this.idTokenProvider});

  final ApiClient? api;
  final Future<String> Function()? idTokenProvider;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

enum _HistoryState { loading, signedOut, error, ready }

class _HistoryTabState extends State<HistoryTab> {
  late final ApiClient _apiClient = widget.api ?? ApiClient();
  late final AuthSession _session = AuthSession(api: _apiClient);
  _HistoryState _state = _HistoryState.loading;
  List<ServiceRequestRecord> _requests = const [];
  Map<int, int> _unreadByOffer = const {};

  @override
  void initState() {
    super.initState();
    _load();
    PushService.instance.chatActivity.addListener(_refreshUnread);
  }

  @override
  void dispose() {
    PushService.instance.chatActivity.removeListener(_refreshUnread);
    super.dispose();
  }

  /// Unread chat counts per offer. Best effort: History works without them.
  Future<void> _refreshUnread() async {
    try {
      final chats = await _session.authorized(_apiClient.getConversations);
      if (mounted) setState(() => _unreadByOffer = {for (final c in chats.conversations) c.offerId: c.unreadCount});
    } catch (_) {
      // leave the counts as they were
    }
  }

  Future<void> _openChat(AcceptedOffer offer) async {
    try {
      final chat = await _session.authorized((token) => _apiClient.openConversation(token, offer.offerId));
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => ConversationScreen(session: _session, conversationId: chat.id, otherName: chat.otherName),
      ));
      if (mounted) _refreshUnread();
    } on SessionExpiredException {
      if (mounted) setState(() => _state = _HistoryState.signedOut);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reach the server. Check your connection and try again.')),
        );
      }
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _state = _HistoryState.loading);
    try {
      if (!await AuthStorage.isLoggedIn()) {
        if (mounted) setState(() => _state = _HistoryState.signedOut);
        return;
      }
      final requests = await _session.authorized(_apiClient.getMyServiceRequests);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _state = _HistoryState.ready;
      });
      _refreshUnread();
    } on SessionExpiredException {
      if (mounted) setState(() => _state = _HistoryState.signedOut);
    } catch (_) {
      if (mounted) setState(() => _state = _HistoryState.error);
    }
  }

  Future<void> _signIn() async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClientSignInScreen(
          api: _apiClient,
          idTokenProvider: widget.idTokenProvider,
          title: 'Sign in to see your requests',
          message: 'Your requests, the providers who accept them and your job history are kept with your Google account.',
        ),
      ),
    );
    if (signedIn == true) _load();
  }

  Future<void> _markComplete(ServiceRequestRecord request, AcceptedOffer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark job complete?'),
        content: Text(
          'Is the job with ${offer.providerName} finished? Only mark it complete once the work is done.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Not yet')),
          TextButton(
            key: const Key('confirm-complete'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, it is done'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _session.authorized((token) => _apiClient.completeServiceRequest(token, request.id, offer.offerId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Marked complete with ${offer.providerName}.')));
      await _load();
    } on SessionExpiredException {
      if (mounted) setState(() => _state = _HistoryState.signedOut);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reach the server. Check your connection and try again.')),
        );
      }
    }
  }

  Widget _messageCard({required Widget child}) {
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
          child: child,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _HistoryState.loading:
        return const Center(child: CircularProgressIndicator(color: AppColors.turquoise));
      case _HistoryState.signedOut:
        return _messageCard(
          child: Column(
            children: [
              Icon(Icons.history_outlined, size: 36, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(
                'Sign in to see your requests.',
                key: const Key('history-signed-out'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              TextButton(
                key: const Key('history-sign-in'),
                onPressed: _signIn,
                child: const Text('Sign in with Google', style: TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      case _HistoryState.error:
        return _messageCard(
          child: Column(
            children: [
              Text('Could not load your requests right now.', style: TextStyle(fontSize: 14, color: AppColors.muted)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _load,
                child: const Text('Retry', style: TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      case _HistoryState.ready:
        return RefreshIndicator(
          color: AppColors.turquoise,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Your requests',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.navy),
              ),
              const SizedBox(height: 8),
              Text(
                "Every request you've submitted. When a provider accepts, you can message them right here.",
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              if (_requests.isEmpty)
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
                        "No requests yet. Once you submit one, it'll show up here.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                    ],
                  ),
                )
              else
                for (final request in _requests) ...[
                  ServiceRequestCard(
                    request: request,
                    onMarkComplete: (offer) => _markComplete(request, offer),
                    onMessage: _openChat,
                    unreadByOffer: _unreadByOffer,
                  ),
                  const SizedBox(height: 14),
                ],
            ],
          ),
        );
    }
  }
}

/// Public (not `_`-prefixed) so it can be pumped directly in widget tests
/// with a hand-built [ServiceRequestRecord] rather than needing to mock the
/// network call the History tab makes to fetch real data.
class ServiceRequestCard extends StatelessWidget {
  const ServiceRequestCard({
    super.key,
    required this.request,
    this.onMarkComplete,
    this.onMessage,
    this.unreadByOffer = const {},
  });

  final ServiceRequestRecord request;

  /// Called when the client taps "Message" next to a provider who accepted.
  final ValueChanged<AcceptedOffer>? onMessage;

  /// Unread chat messages per accepted offer (by offer id).
  final Map<int, int> unreadByOffer;

  /// Called when the client taps "Mark job complete" next to a provider who accepted.
  final ValueChanged<AcceptedOffer>? onMarkComplete;

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
                const SizedBox(height: 6),
                _StatusPill(request: request),
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
                for (final offer in request.acceptedOffers) ...[
                  const SizedBox(height: 12),
                  Column(
                    key: Key('accepted-${offer.offerId}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.check_circle_outline, size: 16, color: AppColors.turquoise),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            offer.providerName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy),
                          ),
                        ),
                      ]),
                      Wrap(spacing: 4, children: [
                        if (onMessage != null)
                          TextButton.icon(
                            key: Key('message-${offer.offerId}'),
                            onPressed: () => onMessage!(offer),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                            icon: const Icon(Icons.chat_bubble_outline, size: 16, color: AppColors.turquoise),
                            label: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Text('Message', style: TextStyle(fontSize: 12, color: AppColors.turquoise, fontWeight: FontWeight.w600)),
                              if ((unreadByOffer[offer.offerId] ?? 0) > 0) ...[
                                const SizedBox(width: 6),
                                _UnreadBadge(count: unreadByOffer[offer.offerId]!, key: Key('unread-${offer.offerId}')),
                              ],
                            ]),
                          ),
                        if (offer.jobCompleted)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Text('Completed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF15803D))),
                          )
                        else if (offer.canComplete && onMarkComplete != null)
                          TextButton(
                            key: Key('complete-${offer.offerId}'),
                            onPressed: () => onMarkComplete!(offer),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                            child: const Text(
                              'Mark job complete',
                              style: TextStyle(fontSize: 12, color: AppColors.turquoise, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ]),
                    ],
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

/// The request's status in words: "Waiting for a provider", "Accepted by (name)" or "Completed".
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.request});

  final ServiceRequestRecord request;

  @override
  Widget build(BuildContext context) {
    final status = requestStatusOf(request);
    final color = switch (status) {
      RequestStatus.waiting => const Color(0xFFB45309),
      RequestStatus.waitlisted => const Color(0xFFB45309),
      RequestStatus.accepted => const Color(0xFF0F766E),
      RequestStatus.completed => const Color(0xFF15803D),
    };
    return Container(
      key: const Key('request-status'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        requestStatusLabel(request),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// A small round count of unread messages.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: const Color(0xFFBA1A1A), borderRadius: BorderRadius.circular(10)),
      child: Text(count > 99 ? '99+' : '$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.white)),
    );
  }
}
