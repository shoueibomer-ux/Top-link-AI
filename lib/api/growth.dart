/// Where a request came from, sent with it so the growth dashboard can count it (see growth.attribution on the
/// server): `seo` (a website page), `seasonal` (a reminder) or `invite`, with which page, campaign or code.
class RequestAttribution {
  const RequestAttribution({required this.source, this.ref = ''});

  final String source;
  final String ref;

  @override
  bool operator ==(Object other) => other is RequestAttribution && other.source == source && other.ref == ref;

  @override
  int get hashCode => Object.hash(source, ref);
}

/// The signed-in client's own invite link (growth.views.InviteView).
class InviteInfo {
  const InviteInfo({required this.code, required this.url, required this.shareText, this.signups = 0});

  factory InviteInfo.fromJson(Map<String, dynamic> json) => InviteInfo(
        code: json['code'] as String? ?? '',
        url: json['url'] as String? ?? '',
        shareText: json['share_text'] as String? ?? '',
        signups: json['signups'] as int? ?? 0,
      );

  final String code;
  final String url;
  final String shareText;

  /// How many people have signed up with this link.
  final int signups;

  /// The link for sharing one provider: the same invite, with the provider named on the page it opens.
  String providerUrl(int providerId) => Uri.parse(url).replace(queryParameters: {'provider': '$providerId'}).toString();
}

/// The server refused an invite code (unknown, the person's own, or the account isn't new). Not worth retrying.
class InviteClaimRejected implements Exception {
  InviteClaimRejected(this.message);

  final String message;

  @override
  String toString() => message;
}
