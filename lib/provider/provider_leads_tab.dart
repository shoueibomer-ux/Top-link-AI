import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/provider_profile.dart';
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
  const ProviderLeadsTab({super.key, required this.session, required this.onSessionExpired});

  final AuthSession session;
  final VoidCallback onSessionExpired;

  @override
  State<ProviderLeadsTab> createState() => _ProviderLeadsTabState();
}

class _ProviderLeadsTabState extends State<ProviderLeadsTab> {
  List<ProviderLead>? _leads;
  String? _error;
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
        builder: (_) => ConversationScreen(session: widget.session, conversationId: chat.id, otherName: chat.otherName),
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
            'Client requests sent to you. We also text you; reply YES to accept.',
            style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
          ),
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
              LeadCard(lead: lead, onMessage: _openChat, unread: _unreadByOffer[lead.offerId] ?? 0),
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

/// One lead. Public so tests can pump it with a hand-built [ProviderLead].
class LeadCard extends StatelessWidget {
  const LeadCard({super.key, required this.lead, this.onMessage, this.unread = 0});

  final ProviderLead lead;

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
