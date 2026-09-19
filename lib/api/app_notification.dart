/// A notification returned by GET /api/notifications/
/// (notifications.views.NotificationListView). Named AppNotification to
/// avoid colliding with Flutter's own Notification widget class.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.category,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String?;
    return AppNotification(
      id: json['id'] as int,
      title: json['title'] as String,
      body: json['body'] as String? ?? '',
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      // Blank string from the backend means "no category" — normalize to
      // null so callers can just check for non-null.
      category: (category == null || category.isEmpty) ? null : category,
    );
  }

  final int id;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;

  // Category slug this notification is about, if any — lets the UI deep-link
  // to that category's detail page when tapped (see ServiceCategory.slug).
  final String? category;
}

class NotificationsResult {
  const NotificationsResult({required this.unreadCount, required this.notifications});

  factory NotificationsResult.fromJson(Map<String, dynamic> json) {
    final items = (json['notifications'] as List<dynamic>)
        .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
        .toList();
    return NotificationsResult(
      unreadCount: json['unread_count'] as int? ?? 0,
      notifications: items,
    );
  }

  final int unreadCount;
  final List<AppNotification> notifications;
}
