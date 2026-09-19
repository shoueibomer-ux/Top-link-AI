import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/app_notification.dart';
import '../app_colors.dart';
import '../onboarding/category_detail_page.dart';
import '../onboarding/service_category.dart';
import '../subscription/device_id.dart';

/// Bell icon backed by real data (notifications.views.NotificationListView) —
/// the badge only shows when there's an actual unread notification, and
/// tapping it opens a real list rather than a "coming soon" message.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _apiClient = ApiClient();
  String? _deviceId;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final deviceId = await getDeviceId();
      final result = await _apiClient.getNotifications(deviceId);
      if (!mounted) return;
      setState(() {
        _deviceId = deviceId;
        _unreadCount = result.unreadCount;
      });
    } catch (_) {
      // Notifications are a nice-to-have — a failed fetch just leaves the
      // badge hidden instead of surfacing an error on every screen load.
    }
  }

  Future<void> _openPanel() async {
    final deviceId = _deviceId ?? await getDeviceId();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _NotificationPanel(
        apiClient: _apiClient,
        deviceId: deviceId,
        onSelectCategory: (category) {
          // Close the sheet first, then navigate from this widget's own
          // (stable) context — the sheet's context stops being valid the
          // instant it's popped.
          Navigator.of(sheetContext).pop();
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => CategoryDetailPage(category: category)),
            );
          }
        },
      ),
    );

    if (_unreadCount > 0) {
      try {
        await _apiClient.markNotificationsRead(deviceId);
      } catch (_) {
        // Best-effort — the badge will just re-show next load if this fails.
      }
      if (mounted) setState(() => _unreadCount = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _unreadCount > 0
          ? const Badge(
              backgroundColor: AppColors.turquoise,
              smallSize: 9,
              child: Icon(Icons.notifications_outlined),
            )
          : const Icon(Icons.notifications_outlined),
      color: AppColors.white,
      tooltip: 'Notifications',
      onPressed: _openPanel,
    );
  }
}

class _NotificationPanel extends StatefulWidget {
  const _NotificationPanel({
    required this.apiClient,
    required this.deviceId,
    required this.onSelectCategory,
  });

  final ApiClient apiClient;
  final String deviceId;
  final ValueChanged<ServiceCategory> onSelectCategory;

  @override
  State<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel> {
  late final Future<NotificationsResult> _future = widget.apiClient.getNotifications(widget.deviceId);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notifications',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: FutureBuilder<NotificationsResult>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator(color: AppColors.turquoise)),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Could not load notifications right now.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    );
                  }
                  final items = snapshot.data!.notifications;
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        "No notifications yet — we'll let you know when there's something new.",
                        style: TextStyle(color: AppColors.muted),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 24, color: Color(0xFFE1E8EF)),
                    itemBuilder: (context, index) => _NotificationTile(
                      notification: items[index],
                      onSelectCategory: widget.onSelectCategory,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onSelectCategory});

  final AppNotification notification;
  final ValueChanged<ServiceCategory> onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final categorySlug = notification.category;
    final category = categorySlug == null ? null : findCategoryBySlug(categorySlug);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 5),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: notification.isRead ? Colors.transparent : AppColors.turquoise,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification.title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy),
              ),
              if (notification.body.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(notification.body, style: TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
              const SizedBox(height: 3),
              Text(_relativeTime(notification.createdAt), style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ),
        // Only notifications tied to a real category are navigable — e.g.
        // the welcome message isn't about anything to open a detail view for.
        if (category != null) ...[
          const SizedBox(width: 4),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.chevron_right, size: 18, color: AppColors.navy),
          ),
        ],
      ],
    );

    if (category == null) return row;

    // The InkWell wraps the row itself (the widget actually rendered as the
    // list item), not just a surrounding padding box, so the whole tile —
    // not a sliver of it — is tappable.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelectCategory(category),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: row,
        ),
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().toUtc().difference(time.toUtc());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  return '${diff.inDays} d ago';
}
