import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/provider_profile.dart';
import '../api/reviews.dart';
import '../widgets/stars.dart';
import '../messaging/conversation_screen.dart';
import '../messaging/push_service.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import 'provider_session.dart';

/// The provider's lead list: the client requests offered to them, newest first.
/// The client's description and name appear only after the provider accepts
/// (by replying YES to the text, or when a Tabmatch admin records it); their
/// phone number is never shown here.
class ProviderLeadsTab extends StatefulWidget {
  const ProviderLeadsTab({super.key, required this.session, required this.onSessionExpired, this.rating = const RatingSummary()});

  /// The provider's own average rating, shown under the heading once they have a review.
  final RatingSummary rating;
  final AuthSession session;
  final VoidCallback onSessionExpired;

  @override
  State<ProviderLeadsTab> createState() => _ProviderLeadsTabState();
}

class _ProviderLeadsTabState extends State<ProviderLeadsTab> {
  List<ProviderLead>? _leads;
  String? _error;
  Map<int, int> _unreadByOffer = const {};

  /// Leads whose Accept / Decline is being sent right now (their buttons wait).
  final _responding = <int>{};

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

  /// Unread chat counts per offer. Best effort: the lead list works without them.
  Future<void> _refreshUnread() async {
    try {
      final chats = await widget.session.authorized(widget.session.api.getConversations);
      if (mounted) setState(() => _unreadByOffer = {for (final c in chats.conversations) c.offerId: c.unreadCount});
    } catch (_) {
      // leave the counts as they were
    }
  }

  Future<void> _openChat(ProviderLead lead) async {
    try {
      final chat = await widget.session.authorized((token) => widget.session.api.openConversation(token, lead.offerId));
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => ConversationScreen(
          session: widget.session,
          conversationId: chat.id,
          otherName: chat.otherName,
          requestSummary: chat.requestSummary,
        ),
      ));
      if (mounted) _refreshUnread();
    } on SessionExpiredException {
      widget.onSessionExpired();
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

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Accept or decline from the card: the same answer as replying YES / NO to the text.
  Future<void> _respond(ProviderLead lead, bool accept) async {
    if (_responding.contains(lead.offerId)) return;
    if (!accept) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Decline this request?'),
          content: const Text("You won't be able to change your answer."),
          actions: [
            TextButton(
              key: const Key('decline-keep'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep it'),
            ),
            TextButton(
              key: const Key('decline-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Decline'),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }
    setState(() => _responding.add(lead.offerId));
    try {
      final updated = await widget.session.authorized(
        (token) => widget.session.api.respondToLead(token, lead.offerId, accept: accept),
      );
      if (!mounted) return;
      setState(() => _leads = [
            for (final l in _leads ?? const <ProviderLead>[]) l.offerId == updated.offerId ? updated : l,
          ]);
      _toast(accept ? 'Accepted. You can message ${updated.clientName ?? 'the client'} now.' : 'Declined.');
      // The first lead a provider accepts is when notifications start to matter to them.
      if (accept) unawaited(PushService.instance.askAfterFirstRequest());
    } on SessionExpiredException {
      widget.onSessionExpired();
    } on ApiException catch (e) {
      _toast(e.message);
      await _load(); // e.g. it was already answered by text: show how it stands now
    } catch (_) {
      _toast('Could not reach the server. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _responding.remove(lead.offerId));
    }
  }

  Future<void> _load() async {
    try {
      final leads = await widget.session.authorized(widget.session.api.getProviderLeads);
      if (!mounted) return;
      setState(() {
        _leads = leads;
        _error = null;
      });
      _refreshUnread();
    } on SessionExpiredException {
      widget.onSessionExpired();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server. Check your connection and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final leads = _leads;
    if (leads == null && _error == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.turquoise));
    }
    return RefreshIndicator(
      color: AppColors.turquoise,
      onRefresh: _load,
      child: ListView(
        key: const Key('provider-leads-list'),
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Your leads',
            key: Key('provider-leads-title'),
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navy),
          ),
          const SizedBox(height: 6),
          Text(
            'Client requests sent to you. Accept or decline here, or reply YES or NO to the text we send you.',
            style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
          ),
          if (widget.rating.hasReviews) ...[
            const SizedBox(height: 8),
            KeyedSubtree(
              key: const Key('leads-rating'),
              child: Row(children: [
                Text('Your rating  ', style: TextStyle(fontSize: 13, color: AppColors.mutedText)),
                RatingLine(rating: widget.rating, fontSize: 13),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          if (_error != null)
            _Note(text: _error!, key: const Key('provider-leads-error'))
          else if (leads!.isEmpty)
            const _Note(
              text: "No requests yet. When a client's request matches your services and cities, it appears here.",
              key: Key('provider-leads-empty'),
            )
          else
            for (final lead in leads) ...[
              LeadCard(
                lead: lead,
                onMessage: _openChat,
                unread: _unreadByOffer[lead.offerId] ?? 0,
                onAccept: (l) => _respond(l, true),
                onDecline: (l) => _respond(l, false),
                responding: _responding.contains(lead.offerId),
              ),
              const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(kRadius), boxShadow: kCardShadow),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.muted)),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Oct 20, 3:49 PM", in the phone's time.
String _receivedLabel(DateTime sent) {
  final t = sent.toLocal();
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${_months[t.month - 1]} ${t.day}, $hour:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// One lead. Public so tests can pump it with a hand-built [ProviderLead].
class LeadCard extends StatelessWidget {
  const LeadCard({
    super.key,
    required this.lead,
    this.onMessage,
    this.unread = 0,
    this.onAccept,
    this.onDecline,
    this.responding = false,
  });

  final ProviderLead lead;

  /// Called when the provider taps Accept / Decline on a lead that is waiting for their answer.
  final ValueChanged<ProviderLead>? onAccept;
  final ValueChanged<ProviderLead>? onDecline;

  /// Their answer is being sent: both buttons wait.
  final bool responding;

  /// Called when the provider taps "Message" on an accepted lead.
  final ValueChanged<ProviderLead>? onMessage;

  /// Unread chat messages for this lead.
  final int unread;

  static const _urgency = {
    'today': 'Needed today',
    'this_week': 'This week',
    'exploring': 'Just exploring',
  };

  (String, Color) get _status => switch (lead.status) {
        LeadStatus.awaitingReply => ('Awaiting your reply', const Color(0xFFB45309)),
        LeadStatus.accepted => (lead.jobCompleted ? 'Completed' : 'Accepted', const Color(0xFF15803D)),
        LeadStatus.declined => ('Declined', AppColors.muted),
        LeadStatus.expired => ('Expired', AppColors.muted),
      };

  @override
  Widget build(BuildContext context) {
    final (label, color) = _status;
    final urgency = _urgency[lead.urgency];
    return Container(
      key: Key('lead-${lead.offerId}'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(kRadius), boxShadow: kCardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  lead.serviceName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [lead.city, ?urgency].join(' · '),
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          // When it came and its number (the one to quote in a text reply), so two requests are never alike.
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              [if (lead.sentAt != null) 'Received ${_receivedLabel(lead.sentAt!)}', 'Request #${lead.ref}'].join(' · '),
              key: Key('lead-received-${lead.offerId}'),
              style: TextStyle(fontSize: 12, color: AppColors.mutedText),
            ),
          ),
          if (lead.clientName != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: AppColors.turquoise),
                const SizedBox(width: 6),
                Text(lead.clientName!, style: const TextStyle(fontSize: 13, color: AppColors.navy)),
              ],
            ),
          ],
          if (lead.description != null && lead.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(lead.description!, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.navy)),
          ],
          if (lead.location != null && lead.location!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 16, color: AppColors.turquoise),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(lead.location!, key: Key('lead-location-${lead.offerId}'), style: const TextStyle(fontSize: 13, color: AppColors.navy)),
                ),
              ],
            ),
          ],
          if (lead.status == LeadStatus.awaitingReply && onAccept != null && onDecline != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('decline-lead-${lead.offerId}'),
                    onPressed: responding ? null : () => onDecline!(lead),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: AppColors.navy,
                      side: BorderSide(color: AppColors.navy.withValues(alpha: 0.25)),
                    ),
                    child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: Key('accept-lead-${lead.offerId}'),
                    onPressed: responding ? null : () => onAccept!(lead),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: AppColors.turquoise,
                      disabledBackgroundColor: AppColors.turquoise.withValues(alpha: 0.4),
                    ),
                    child: responding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppColors.white)),
                          )
                        : const Text('Accept', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Or reply YES ${lead.ref} or NO ${lead.ref} to the text we sent.',
              style: TextStyle(fontSize: 12, color: AppColors.mutedText),
            ),
          ],
          if (lead.status == LeadStatus.accepted && onMessage != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: Key('message-lead-${lead.offerId}'),
              onPressed: () => onMessage!(lead),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
              icon: const Icon(Icons.chat_bubble_outline, size: 16, color: AppColors.turquoise),
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Message', style: TextStyle(fontSize: 13, color: AppColors.turquoise, fontWeight: FontWeight.w600)),
                if (unread > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    key: Key('unread-lead-${lead.offerId}'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFFBA1A1A), borderRadius: BorderRadius.circular(10)),
                    child: Text(unread > 99 ? '99+' : '$unread', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.white)),
                  ),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
