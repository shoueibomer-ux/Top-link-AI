import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/messaging.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../provider/provider_session.dart';

/// A photo the person picked, already shrunk and re-encoded (which also drops its location data).
class PickedPhoto {
  const PickedPhoto({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

Future<PickedPhoto?> pickPhotoFromDevice(ImageSource source) async {
  final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
  if (file == null) return null;
  final path = file.path.toLowerCase();
  final type = path.endsWith('.png')
      ? 'image/png'
      : path.endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg';
  return PickedPhoto(bytes: await file.readAsBytes(), contentType: type);
}

Future<bool> openPhoneDialer(Uri uri) => launchUrl(uri);

/// The chat between a client and a provider who accepted their request. New messages arrive by asking the
/// server every few seconds *while this screen is open and the app is in front*; a push notification wakes
/// the app when it isn't. Messages are fetched with a cursor (only what is newer than the last one seen).
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.session,
    required this.conversationId,
    this.otherName = '',
    this.pollInterval = const Duration(seconds: 4),
    this.pickPhoto = pickPhotoFromDevice,
    this.openDialer = openPhoneDialer,
  });

  final AuthSession session;
  final int conversationId;
  final String otherName;
  final Duration pollInterval;

  /// Tests pass fakes for these two.
  final Future<PickedPhoto?> Function(ImageSource source) pickPhoto;
  final Future<bool> Function(Uri uri) openDialer;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _messages = <ChatMessage>[];
  ChatPage? _page;
  Timer? _timer;
  bool _loading = true;
  bool _sending = false;
  bool _polling = false;
  String? _loadError;

  ApiClient get _api => widget.session.api;
  int? get _lastId => _messages.isEmpty ? null : _messages.last.id;
  bool get _blockedByMe => _page?.blockedByMe ?? false;
  bool get _canSend => _page?.canSend ?? true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _poll();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.pollInterval, (_) => _poll());
  }

  Future<T?> _call<T>(Future<T> Function(String token) action) async {
    try {
      return await widget.session.authorized(action);
    } on SessionExpiredException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your session expired. Please sign in again.')));
        Navigator.of(context).maybePop();
      }
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final page = await _call((t) => _api.getMessages(t, widget.conversationId));
      if (page == null || !mounted) return;
      setState(() {
        _page = page;
        _messages
          ..clear()
          ..addAll(page.messages);
        _loading = false;
        _loadError = null;
      });
      _startPolling();
      _markRead();
    } on ApiException catch (e) {
      _failLoading(e.message);
    } catch (_) {
      _failLoading('Could not reach the server. Check your connection and try again.');
    }
  }

  void _failLoading(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadError = message;
    });
  }

  Future<void> _poll() async {
    if (_polling || _loading || _sending || !mounted) return;
    _polling = true;
    try {
      final page = await _call((t) => _api.getMessages(t, widget.conversationId, sinceId: _lastId));
      if (page == null || !mounted) return;
      final known = {for (final m in _messages) m.id};
      final fresh = page.messages.where((m) => !known.contains(m.id)).toList();
      setState(() {
        _page = page;
        _messages.addAll(fresh);
      });
      if (fresh.any((m) => !m.mine)) _markRead();
    } catch (_) {
      // A missed poll is fine; the next one will catch up.
    } finally {
      _polling = false;
    }
  }

  Future<void> _markRead() async {
    final last = _lastId;
    if (last == null) return;
    try {
      await _call((t) => _api.markConversationRead(t, widget.conversationId, lastId: last));
    } catch (_) {
      // Unread counts catch up next time.
    }
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Makes sure the person has agreed to the chat rules, asking if they haven't. False if they decline.
  Future<bool> _ensureTerms() async {
    if (_page?.termsAccepted == true) return true;
    final text = await _call((t) => _api.getChatTerms(t)) ?? '';
    if (!mounted) return false;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chat rules'),
        content: Text(text),
        actions: [
          TextButton(key: const Key('terms-decline'), onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Not now')),
          TextButton(key: const Key('terms-agree'), onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('I agree')),
        ],
      ),
    );
    if (agreed != true) return false;
    await _call((t) => _api.acceptChatTerms(t));
    if (mounted && _page != null) {
      setState(() => _page = ChatPage(
            messages: _page!.messages,
            otherName: _page!.otherName,
            blockedByMe: _page!.blockedByMe,
            canSend: _page!.canSend,
            termsAccepted: true,
            photosEnabled: _page!.photosEnabled,
          ));
    }
    return true;
  }

  Future<void> _send({String? photoKey}) async {
    final text = _input.text.trim();
    if ((text.isEmpty && photoKey == null) || _sending) return;
    setState(() => _sending = true);
    try {
      if (!await _ensureTerms()) return;
      Future<ChatMessage?> go() => _call((t) => _api.sendMessage(t, widget.conversationId, body: text, photoKey: photoKey));
      ChatMessage? sent;
      try {
        sent = await go();
      } on ChatTermsRequired {
        if (!await _ensureTerms()) return;
        sent = await go();
      }
      if (sent == null || !mounted) return;
      final message = sent;
      setState(() {
        if (!_messages.any((m) => m.id == message.id)) _messages.add(message);
        _input.clear();
      });
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not reach the server. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(children: [
          ListTile(
            key: const Key('attach-gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose a photo'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
          ListTile(
            key: const Key('attach-camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null || _sending) return;
    final photo = await widget.pickPhoto(source);
    if (photo == null || !mounted) return;
    setState(() => _sending = true);
    try {
      if (!await _ensureTerms()) return;
      final upload = await _call((t) => _api.requestPhotoUpload(t, widget.conversationId, photo.contentType));
      if (upload == null) return;
      await _api.uploadPhotoBytes(upload, photo.bytes);
      if (mounted) setState(() => _sending = false);
      await _send(photoKey: upload.key);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('The photo could not be sent. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _report(ChatMessage message) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Report this message'),
        children: [
          for (final entry in kReportReasons.entries)
            SimpleDialogOption(
              key: Key('report-${entry.key}'),
              onPressed: () => Navigator.of(dialogContext).pop(entry.key),
              child: Text(entry.value),
            ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await _call((t) => _api.reportMessage(t, widget.conversationId, message.id, reason));
      _toast('Thanks. We will review this message.');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _toggleBlock() async {
    final blocking = !_blockedByMe;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(blocking ? 'Block this person?' : 'Unblock this person?'),
        content: Text(blocking
            ? 'Neither of you will be able to send messages in this chat. You can unblock them any time.'
            : 'You will both be able to send messages again.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(key: const Key('confirm-block'), onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(blocking ? 'Block' : 'Unblock')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _call((t) => _api.setConversationBlocked(t, widget.conversationId, blocking));
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _call_() async {
    try {
      final info = await _call((t) => _api.getCallInfo(t, widget.conversationId));
      if (info == null) return;
      final opened = await widget.openDialer(Uri(scheme: 'tel', path: info.number));
      if (!opened) _toast('Could not open the phone dialer.');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  static String _time(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final title = _page?.otherName.isNotEmpty == true ? _page!.otherName : widget.otherName;
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: Text(title.isEmpty ? 'Chat' : title, key: const Key('chat-title')),
        actions: [
          IconButton(key: const Key('call-button'), tooltip: 'Call', icon: const Icon(Icons.call_outlined), onPressed: _call_),
          PopupMenuButton<String>(
            key: const Key('chat-menu'),
            onSelected: (_) => _toggleBlock(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'block', child: Text(_blockedByMe ? 'Unblock this person' : 'Block this person')),
            ],
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.turquoise));
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_loadError!, key: const Key('chat-error'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _loadError = null;
                });
                _load();
              },
              child: const Text('Try again'),
            ),
          ]),
        ),
      );
    }
    return Column(children: [
      Expanded(
        child: _messages.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No messages yet. Say hello and agree on the details of the job.',
                    key: const Key('chat-empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                ),
              )
            : ListView.builder(
                key: const Key('chat-list'),
                reverse: true, // the newest message stays in view
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: _messages.length,
                itemBuilder: (context, index) => _bubble(_messages[_messages.length - 1 - index]),
              ),
      ),
      _composer(),
    ]);
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.mine;
    final Widget content;
    if (m.removed) {
      content = Text('Message removed by a moderator', style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.muted));
    } else {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (m.photoUrl != null)
          Padding(
            padding: EdgeInsets.only(bottom: m.body.isEmpty ? 0 : 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                m.photoUrl!,
                key: Key('photo-${m.id}'),
                width: 220,
                fit: BoxFit.cover,
                loadingBuilder: (c, child, progress) => progress == null ? child : const SizedBox(width: 220, height: 140, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                errorBuilder: (c, e, s) => Container(width: 220, height: 100, color: const Color(0x14000000), alignment: Alignment.center, child: Text('Photo unavailable', style: TextStyle(color: AppColors.muted))),
              ),
            ),
          )
        else if (m.body.isEmpty)
          const Text('Photo'),
        if (m.body.isNotEmpty) Text(m.body, style: TextStyle(color: mine ? AppColors.white : AppColors.navy, height: 1.35)),
      ]);
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: mine || m.removed ? null : () => _report(m),
        child: Container(
          key: Key('message-${m.id}'),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: m.removed ? const Color(0x0F000000) : (mine ? AppColors.turquoise : AppColors.white),
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: mine ? null : kCardShadow,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            content,
            const SizedBox(height: 4),
            Text(_time(m.createdAt), style: TextStyle(fontSize: 10, color: mine ? const Color(0xCCFFFFFF) : AppColors.muted)),
          ]),
        ),
      ),
    );
  }

  Widget _composer() {
    if (_blockedByMe) {
      return Container(
        key: const Key('blocked-banner'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        color: AppColors.white,
        child: Row(children: [
          Expanded(child: Text('You blocked this person. Unblock them to chat.', style: TextStyle(color: AppColors.muted))),
          TextButton(onPressed: _toggleBlock, child: const Text('Unblock')),
        ]),
      );
    }
    if (!_canSend) {
      return Container(
        key: const Key('cannot-send-banner'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        color: AppColors.white,
        child: Text("You can't send messages in this conversation.", style: TextStyle(color: AppColors.muted)),
      );
    }
    final canPhoto = _page?.photosEnabled ?? false;
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(children: [
        if (canPhoto)
          IconButton(
            key: const Key('attach-button'),
            tooltip: 'Send a photo',
            icon: const Icon(Icons.photo_outlined, color: AppColors.navy),
            onPressed: _sending ? null : _attach,
          ),
        Expanded(
          child: TextField(
            key: const Key('message-input'),
            controller: _input,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Message', counterText: '', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 8)),
          ),
        ),
        _sending
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.turquoise)))
            : IconButton(
                key: const Key('send-button'),
                tooltip: 'Send',
                icon: Icon(Icons.send_rounded, color: _input.text.trim().isEmpty ? AppColors.muted : AppColors.turquoise),
                onPressed: _input.text.trim().isEmpty ? null : () => _send(),
              ),
      ]),
    );
  }
}
