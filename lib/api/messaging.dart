/// One chat, as the app lists it (messaging.views.ConversationListView). `offerId` is how History cards
/// and the provider's leads find their chat and its unread count.
class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.offerId,
    required this.requestId,
    required this.otherName,
    this.requestSummary = '',
    this.unreadCount = 0,
    this.lastPreview,
    this.blockedByMe = false,
    this.termsAccepted = false,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final last = json['last_message'];
    return ChatConversation(
      id: json['id'] as int,
      offerId: json['offer_id'] as int,
      requestId: json['request_id'] as int? ?? 0,
      otherName: json['other_name'] as String? ?? '',
      requestSummary: json['request_summary'] as String? ?? '',
      unreadCount: json['unread_count'] as int? ?? 0,
      lastPreview: last is Map<String, dynamic> ? last['preview'] as String? : null,
      blockedByMe: json['blocked_by_me'] as bool? ?? false,
      termsAccepted: json['terms_accepted'] as bool? ?? false,
    );
  }

  final int id;
  final int offerId;
  final int requestId;
  final String otherName;

  /// What the chat is about, e.g. "Plumbing · Leaking kitchen sink".
  final String requestSummary;
  final int unreadCount;
  final String? lastPreview;
  final bool blockedByMe;
  final bool termsAccepted;
}

/// One message. A moderator-removed message arrives with [removed] true and nothing else.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.mine,
    required this.createdAt,
    this.body = '',
    this.photoUrl,
    this.removed = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      mine: json['mine'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      body: json['body'] as String? ?? '',
      photoUrl: json['photo_url'] as String?,
      removed: json['removed'] as bool? ?? false,
    );
  }

  final int id;
  final bool mine;
  final DateTime createdAt;
  final String body;
  final String? photoUrl;
  final bool removed;
}

/// A page of messages plus what the screen needs to know about the chat.
class ChatPage {
  const ChatPage({
    required this.messages,
    required this.otherName,
    this.requestSummary = '',
    this.blockedByMe = false,
    this.canSend = true,
    this.termsAccepted = false,
    this.photosEnabled = false,
  });

  factory ChatPage.fromJson(Map<String, dynamic> json) {
    return ChatPage(
      messages: [
        for (final m in json['messages'] as List<dynamic>? ?? const []) ChatMessage.fromJson(m as Map<String, dynamic>),
      ],
      otherName: json['other_name'] as String? ?? '',
      requestSummary: json['request_summary'] as String? ?? '',
      blockedByMe: json['blocked_by_me'] as bool? ?? false,
      canSend: json['can_send'] as bool? ?? true,
      termsAccepted: json['terms_accepted'] as bool? ?? false,
      photosEnabled: json['photos_enabled'] as bool? ?? false,
    );
  }

  final List<ChatMessage> messages;
  final String otherName;
  final String requestSummary;
  final bool blockedByMe;
  final bool canSend;
  final bool termsAccepted;
  final bool photosEnabled;
}

/// A short-lived signed link to upload one photo straight to storage.
class PhotoUpload {
  const PhotoUpload({required this.key, required this.uploadUrl, required this.headers});

  factory PhotoUpload.fromJson(Map<String, dynamic> json) {
    return PhotoUpload(
      key: json['key'] as String,
      uploadUrl: json['upload_url'] as String,
      headers: {for (final e in (json['headers'] as Map<String, dynamic>? ?? const {}).entries) e.key: e.value.toString()},
    );
  }

  final String key;
  final String uploadUrl;
  final Map<String, String> headers;
}

/// How to call the other person (messaging.views.CallView). Phase 1 is always `direct`: the number for the
/// phone's dialer. Phase 2 (masked calls) will change what the server returns here, not the app.
class CallInfo {
  const CallInfo({required this.mode, required this.number, required this.name});

  factory CallInfo.fromJson(Map<String, dynamic> json) {
    return CallInfo(
      mode: json['mode'] as String? ?? 'direct',
      number: json['number'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }

  final String mode;
  final String number;
  final String name;
}

/// The reasons offered when reporting a message (values match messaging.models.MessageReport).
const kReportReasons = <String, String>{
  'spam': 'Spam',
  'harassment': 'Harassment or abuse',
  'inappropriate': 'Inappropriate content',
  'scam': 'Scam or fraud',
  'other': 'Something else',
};
