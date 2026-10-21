import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_colors.dart';
import '../provider/google_sign_in_service.dart';
import '../provider/provider_session.dart';
import '../role/app_role.dart';

/// The word that has to be typed (the server checks it too).
const kDeleteConfirmWord = 'DELETE';

/// What the person is told, so it is the same everywhere and a test can check it.
List<String> deletedItems({required bool isProvider}) => isProvider
    ? const [
        'Your business profile: name, phone, email, description, services and cities',
        'Your chats and the photos in them',
        'Your replies to reviews',
        'Your sign-in and notification settings',
      ]
    : const [
        'Your name, email and sign-in',
        'Your chats and the photos in them',
        'Your saved providers',
        'The phone number, description and location on your requests',
      ];

String keptNote({required bool isProvider}) => isProvider
    ? 'Reviews clients wrote about you stay, without your replies, so ratings stay fair. Anonymous records of requests you were offered also stay.'
    : 'Reviews you wrote stay, without your name, so a provider\'s ratings stay fair. Anonymous records of your requests (with no phone number, description or location) also stay.';

/// "Delete my account": explains what goes, makes the person type DELETE, deletes, and signs them out to the
/// first screen. Returns true if the account was deleted. [afterDeleted] is how the app leaves (tests replace it).
Future<bool> startDeleteAccount(
  BuildContext context, {
  required AuthSession session,
  required bool isProvider,
  Future<void> Function(BuildContext context)? afterDeleted,
}) async {
  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DeleteAccountDialog(session: session, isProvider: isProvider),
  );
  if (deleted != true || !context.mounted) return deleted == true;
  await (afterDeleted ?? leaveAfterDeletion)(context);
  return true;
}

/// Signs out of Google too (so the next sign-in asks which account), forgets the role, and goes to the first screen.
Future<void> leaveAfterDeletion(BuildContext context) async {
  await GoogleSignInService.signOut();
  if (context.mounted) await switchRole(context);
}

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.session, required this.isProvider});

  final AuthSession session;
  final bool isProvider;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _word = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  bool get _confirmed => _word.text.trim() == kDeleteConfirmWord;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.authorized((token) => widget.session.api.deleteMyAccount(token, confirm: kDeleteConfirmWord));
      if (mounted) Navigator.of(context).pop(true);
    } on SessionExpiredException {
      if (mounted) setState(() => _error = 'Your session has expired. Sign in again, then delete your account.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = deletedItems(isProvider: widget.isProvider);
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This permanently deletes:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('•  '),
                  Expanded(child: Text(item, key: Key('deletes-${items.indexOf(item)}'))),
                ]),
              ),
            const SizedBox(height: 8),
            Text(keptNote(isProvider: widget.isProvider), key: const Key('kept-note'), style: TextStyle(fontSize: 13, color: AppColors.mutedText)),
            const SizedBox(height: 12),
            const Text("This can't be undone.", style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFBA1A1A))),
            const SizedBox(height: 12),
            TextField(
              key: const Key('delete-confirm-field'),
              controller: _word,
              enabled: !_busy,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Type $kDeleteConfirmWord to confirm',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, key: const Key('delete-error'), style: const TextStyle(color: Color(0xFFBA1A1A), fontSize: 13)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('delete-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('delete-confirm'),
          onPressed: (_confirmed && !_busy) ? _delete : null,
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFBA1A1A)),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Delete my account'),
        ),
      ],
    );
  }
}
