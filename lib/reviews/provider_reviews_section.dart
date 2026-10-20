import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/reviews.dart';
import '../app_colors.dart';
import '../provider/provider_session.dart';
import '../widgets/stars.dart';
import 'review_ui.dart';

/// "Your reviews" on the provider's profile: their rating, and every review with a button to post the one
/// public reply they get per review.
class ProviderReviewsSection extends StatefulWidget {
  const ProviderReviewsSection({super.key, required this.session, this.onSessionExpired});

  final AuthSession session;
  final VoidCallback? onSessionExpired;

  @override
  State<ProviderReviewsSection> createState() => _ProviderReviewsSectionState();
}

class _ProviderReviewsSectionState extends State<ProviderReviewsSection> {
  MyReviews? _reviews;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reviews = await widget.session.authorized(widget.session.api.getMyReviews);
      if (mounted) {
        setState(() {
          _reviews = reviews;
          _error = null;
        });
      }
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
    } catch (e) {
      if (mounted) setState(() => _error = reviewErrorText(e));
    }
  }

  Future<void> _reply(Review review) async {
    final saved = await showReplySheet(context, session: widget.session, review: review);
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your reply is now public.')));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final reviews = _reviews;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Your reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
      const SizedBox(height: 4),
      if (reviews != null) KeyedSubtree(key: const Key('my-rating'), child: RatingLine(rating: reviews.summary, fontSize: 14)),
      const SizedBox(height: 10),
      if (_error != null)
        Row(children: [
          Expanded(child: Text(_error!, key: const Key('my-reviews-error'), style: TextStyle(fontSize: 13, color: AppColors.mutedText))),
          TextButton(key: const Key('my-reviews-retry'), onPressed: _load, child: const Text('Try again')),
        ])
      else if (reviews == null)
        const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: AppColors.turquoise)))
      else if (reviews.reviews.isEmpty)
        Text(
          'No reviews yet. Clients can rate you once a job is marked complete.',
          key: const Key('my-reviews-empty'),
          style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.mutedText),
        )
      else
        for (final review in reviews.reviews) ...[
          ReviewTile(review: review, onReply: () => _reply(review)),
          const SizedBox(height: 12),
        ],
    ]);
  }
}
