import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/chat_refine_result.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../onboarding/service_category.dart';
import '../subscription/device_id.dart';
import '../widgets/real_provider_card.dart';

/// Free-text alternative to the fixed category-tap onboarding flow (see
/// provider_search.chat_service.refine_request / ChatRefineView) — the user
/// describes what they need in their own words and the backend extracts a
/// category/urgency, then immediately searches providers for it.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  const _ChatMessage.user(this.text) : isUser = true, result = null;
  const _ChatMessage.assistant(this.text, this.result) : isUser = false;

  final bool isUser;
  final String text;
  final ChatRefineResult? result;
}

class _ChatScreenState extends State<ChatScreen> {
  final _apiClient = ApiClient();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    _textController.clear();
    setState(() {
      _messages.add(_ChatMessage.user(text));
      _sending = true;
    });
    _scrollToBottom();

    try {
      final deviceId = await getDeviceId();
      final result = await _apiClient.refineChatMessage(message: text, deviceId: deviceId);
      final category = result.category == null ? null : findCategoryBySlug(result.category!);
      final reply = category == null
          ? "I couldn't quite tell what kind of service you need — try naming a trade, like plumbing or electrical."
          : "Got it — sounds like ${category.label.toLowerCase()}, ${_urgencyPhrase(result.urgency)}."
              "${result.providers.isEmpty ? ' No providers turned up nearby yet.' : " Here's who's available:"}";
      setState(() => _messages.add(_ChatMessage.assistant(reply, result)));
    } catch (_) {
      setState(() => _messages.add(
            const _ChatMessage.assistant(
              "Something went wrong reaching the matching service — try again in a moment.",
              null,
            ),
          ));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? const _ChatEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _MessageBubble(message: _messages[index]),
                ),
        ),
        if (_sending)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.turquoise),
            ),
          ),
        _ChatInputBar(controller: _textController, onSend: _send, enabled: !_sending),
      ],
    );
  }
}

String _urgencyPhrase(String urgency) => switch (urgency) {
      'today' => "and it sounds urgent",
      'this_week' => "sometime this week",
      _ => "no particular rush",
    };

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 40, color: AppColors.muted),
            const SizedBox(height: 16),
            const Text(
              'Tell us what you need',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Describe your request in your own words — e.g. "I need a plumber '
              'available this weekend under \$100" — and we\'ll match you instantly.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * (message.isUser ? 0.75 : 0.85);

    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(maxWidth: maxWidth),
          decoration: BoxDecoration(
            color: AppColors.turquoise,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Text(message.text, style: const TextStyle(color: AppColors.white, fontSize: 14)),
        ),
      );
    }

    final result = message.result;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(kRadius),
                boxShadow: kCardShadow,
              ),
              child: Text(message.text, style: const TextStyle(color: AppColors.navy, fontSize: 14)),
            ),
            if (result != null && result.providers.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final provider in result.providers) ...[
                RealProviderCard(provider: provider),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({required this.controller, required this.onSend, required this.enabled});

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(color: AppColors.navy.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'e.g. I need a plumber this weekend, under \$100',
                hintStyle: TextStyle(color: AppColors.muted, fontSize: 13),
                filled: true,
                fillColor: AppColors.lightBackground,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: AppColors.turquoise,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              icon: const Icon(Icons.send, color: AppColors.white, size: 20),
              onPressed: enabled ? onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}
