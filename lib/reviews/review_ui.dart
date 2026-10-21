import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/reviews.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../provider/provider_session.dart';
import '../widgets/stars.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String reviewDate(DateTime d) {
  final local = d.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

const _connectionError = 'Could not reach the server. Check your connection and try again.';

/// A message for an API failure shown inline or in a snackbar. [SessionExpiredException] is left to the caller.
String reviewErrorText(Object error) => error is ApiException ? error.message : _connectionError;

/// One review: stars, who wrote it ("Pat P."), when, the comment, and the provider's reply if there is one.
/// [onReport] adds a flag button (for reviews written by someone else); [onReply] adds a "Reply" button for the
/// reviewed provider while there is no reply yet.
class ReviewTile extends StatelessWidget {
  const ReviewTile({super.key, required this.review, this.onReport, this.onReply});

  final Review review;
  final VoidCallback? onReport;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('review-${review.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(kRadius), boxShadow: kCardShadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          StarRow(rating: review.rating),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              review.clientName,
              key: Key('review-name-${review.id}'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy),
            ),
          ),
          if (onReport != null)
            IconButton(
              key: Key('report-review-${review.id}'),
              tooltip: 'Report this review',
              onPressed: onReport,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.flag_outlined, size: 18, color: AppColors.mutedText),
            ),
        ]),
        const SizedBox(height: 2),
        Text(
          review.edited ? '${reviewDate(review.createdAt)} (edited)' : reviewDate(review.createdAt),
          style: TextStyle(fontSize: 12, color: AppColors.mutedText),
        ),
        if (review.hidden) ...[
          const SizedBox(height: 8),
          const Text(
            'This review was removed by Tabmatch and no longer counts toward the rating.',
            key: Key('review-removed'),
            style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Color(0xFFBA1A1A)),
          ),
        ],
        if (review.comment.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(review.comment, style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.navy)),
        ],
        if (review.reply != null) ...[
          const SizedBox(height: 10),
          Container(
            key: Key('reply-${review.id}'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.lightBackground,
              borderRadius: BorderRadius.circular(12),
              border: const Border(left: BorderSide(color: AppColors.turquoise, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Reply from the provider', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navy)),
              const SizedBox(height: 4),
              Text(review.reply!.text, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.navy)),
            ]),
          ),
        ] else if (onReply != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('reply-button-${review.id}'),
              onPressed: onReply,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 32)),
              icon: const Icon(Icons.reply_rounded, size: 16, color: AppColors.turquoise),
              label: const Text('Reply publicly', style: TextStyle(fontSize: 12, color: AppColors.turquoise, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Bottom sheet where the client rates the provider (1-5 stars, optional comment) or edits an earlier review.
/// Returns the saved review, or null if they closed it.
Future<Review?> showReviewSheet(
  BuildContext context, {
  required AuthSession session,
  required int offerId,
  required String providerName,
  Review? existing,
}) {
  return showModalBottomSheet<Review>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.white,
    builder: (_) => _ReviewSheet(session: session, offerId: offerId, providerName: providerName, existing: existing),
  );
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.session, required this.offerId, required this.providerName, this.existing});

  final AuthSession session;
  final int offerId;
  final String providerName;
  final Review? existing;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late int _rating = widget.existing?.rating ?? 0;
  late final TextEditingController _comment = TextEditingController(text: widget.existing?.comment ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_rating == 0) {
      setState(() => _error = 'Tap a star to choose your rating.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = widget.session.api;
    final text = _comment.text.trim();
    try {
      final saved = await widget.session.authorized((token) => widget.existing == null
          ? api.submitReview(token, widget.offerId, _rating, text)
          : api.updateReview(token, widget.offerId, _rating, text));
      if (mounted) Navigator.of(context).pop(saved);
    } on SessionExpiredException {
      if (mounted) setState(() => _error = 'Your session has expired. Please sign in again.');
    } catch (e) {
      if (mounted) setState(() => _error = reviewErrorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            editing ? 'Edit your review' : 'Rate ${widget.providerName}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy),
          ),
          const SizedBox(height: 4),
          Text(
            editing ? 'You can change this for 7 days after you posted it.' : 'How did the job go? Your review is public and shows your first name and last initial.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.mutedText),
          ),
          const SizedBox(height: 8),
          StarPicker(value: _rating, onChanged: (v) => setState(() => _rating = v)),
          const SizedBox(height: 8),
          TextField(
            key: const Key('review-comment'),
            controller: _comment,
            maxLength: kMaxReviewChars,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Add a comment (optional)', border: OutlineInputBorder()),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, key: const Key('review-error'), style: const TextStyle(color: Color(0xFFBA1A1A), fontSize: 13)),
            ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('review-save'),
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AppColors.turquoise, minimumSize: const Size.fromHeight(48)),
            child: Text(_saving ? 'Saving…' : (editing ? 'Save changes' : 'Post review')),
          ),
        ]),
      ),
    );
  }
}

/// The provider's one public reply. Returns the updated review, or null if they closed it.
Future<Review?> showReplySheet(BuildContext context, {required AuthSession session, required Review review}) {
  return showModalBottomSheet<Review>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.white,
    builder: (_) => _ReplySheet(session: session, review: review),
  );
}

class _ReplySheet extends StatefulWidget {
  const _ReplySheet({required this.session, required this.review});

  final AuthSession session;
  final Review review;

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final _text = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write your reply first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.session.authorized((t) => widget.session.api.replyToReview(t, widget.review.id, text));
      if (mounted) Navigator.of(context).pop(saved);
    } on SessionExpiredException {
      if (mounted) setState(() => _error = 'Your session has expired. Please sign in again.');
    } catch (e) {
      if (mounted) setState(() => _error = reviewErrorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'Reply to ${widget.review.clientName}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy),
          ),
          const SizedBox(height: 4),
          Text(
            'Your reply is public and you can only post one. It can’t be edited afterwards.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.mutedText),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('reply-text'),
            controller: _text,
            maxLength: 1000,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Write your reply', border: OutlineInputBorder()),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, key: const Key('reply-error'), style: const TextStyle(color: Color(0xFFBA1A1A), fontSize: 13)),
            ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('reply-send'),
            onPressed: _saving ? null : _send,
            style: FilledButton.styleFrom(backgroundColor: AppColors.turquoise, minimumSize: const Size.fromHeight(48)),
            child: Text(_saving ? 'Posting…' : 'Post reply'),
          ),
        ]),
      ),
    );
  }
}

/// Asks for a reason, then sends the report. Shows the outcome in a snackbar. Returns true if it was sent.
Future<bool> reportReviewFlow(BuildContext context, {required AuthSession session, required Review review}) async {
  final reason = await showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Report this review'),
      children: [
        for (final entry in kReviewReportReasons.entries)
          SimpleDialogOption(
            key: Key('report-reason-${entry.key}'),
            onPressed: () => Navigator.of(dialogContext).pop(entry.key),
            child: Text(entry.value),
          ),
      ],
    ),
  );
  if (reason == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await session.authorized((t) => session.api.reportReview(t, review.id, reason));
    messenger.showSnackBar(const SnackBar(content: Text('Thanks. We will take a look at this review.')));
    return true;
  } on SessionExpiredException {
    messenger.showSnackBar(const SnackBar(content: Text('Your session has expired. Please sign in again.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(reviewErrorText(e))));
  }
  return false;
}
