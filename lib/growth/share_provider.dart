import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/growth.dart';
import '../app_colors.dart';
import '../provider/provider_session.dart';

/// The message a client shares about a provider they hired: names the provider and links to the client's own
/// invite (with the provider on it), so a friend who signs up through it is counted as their invite.
String providerShareText({required String providerName, required String serviceLabel, required String url}) =>
    'I hired $providerName through Tabmatch for ${serviceLabel.toLowerCase()} and would recommend them. '
    'Find them on Tabmatch: $url';

/// WhatsApp's share link, which opens the app (or WhatsApp Web) with [text] ready to send.
Uri whatsAppShareUri(String text) => Uri.https('wa.me', '/', {'text': text});

/// A new text message with [text] filled in. iOS wants `sms:&body=`, Android `sms:?body=`.
Uri smsShareUri(String text, {TargetPlatform? platform}) {
  final body = Uri.encodeComponent(text);
  return (platform ?? defaultTargetPlatform) == TargetPlatform.iOS ? Uri.parse('sms:&body=$body') : Uri.parse('sms:?body=$body');
}

/// Opens a link outside the app. Tests swap it for a fake.
typedef ExternalLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchExternal(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// "Share this provider": fetches the client's invite link, then offers WhatsApp, a text message, or copying it.
Future<void> showShareProviderSheet(
  BuildContext context, {
  required AuthSession session,
  required int providerId,
  required String providerName,
  required String serviceLabel,
  ExternalLauncher launcher = _launchExternal,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  InviteInfo invite;
  try {
    invite = await session.authorized(session.api.getInvite);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not reach the server. Check your connection and try again.')));
    return;
  }
  final url = invite.providerUrl(providerId);
  final text = providerShareText(providerName: providerName, serviceLabel: serviceLabel, url: url);
  if (!context.mounted) return;
  await showShareLinkSheet(context, title: 'Share $providerName', text: text, url: url, launcher: launcher);
}

/// "Invite friends": the client's own invite link, to send or copy.
Future<void> showInviteFriendsSheet(BuildContext context, {required AuthSession session, ExternalLauncher launcher = _launchExternal}) async {
  final messenger = ScaffoldMessenger.of(context);
  InviteInfo invite;
  try {
    invite = await session.authorized(session.api.getInvite);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not reach the server. Check your connection and try again.')));
    return;
  }
  if (!context.mounted) return;
  final joined = switch (invite.signups) {
    0 => '',
    1 => ' 1 friend has joined with it.',
    final n => ' $n friends have joined with it.',
  };
  await showShareLinkSheet(
    context,
    title: 'Invite friends',
    subtitle: 'Your invite code is ${invite.code}.$joined',
    text: invite.shareText,
    url: invite.url,
    launcher: launcher,
  );
}

/// WhatsApp, a text message, or copy the link.
Future<void> showShareLinkSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String text,
  required String url,
  ExternalLauncher launcher = _launchExternal,
}) {
  final messenger = ScaffoldMessenger.of(context);

  Future<void> open(Uri uri, String app) async {
    var opened = false;
    try {
      opened = await launcher(uri);
    } catch (_) {}
    if (!opened) messenger.showSnackBar(SnackBar(content: Text('Could not open $app on this phone.')));
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, key: const Key('share-subtitle'), style: TextStyle(fontSize: 13, color: AppColors.mutedText)),
            ],
          ]),
        ),
        ListTile(
          key: const Key('share-whatsapp'),
          leading: const Icon(Icons.chat_outlined, color: AppColors.turquoise),
          title: const Text('WhatsApp'),
          onTap: () {
            Navigator.of(sheetContext).pop();
            open(whatsAppShareUri(text), 'WhatsApp');
          },
        ),
        ListTile(
          key: const Key('share-sms'),
          leading: const Icon(Icons.sms_outlined, color: AppColors.turquoise),
          title: const Text('Text message'),
          onTap: () {
            Navigator.of(sheetContext).pop();
            open(smsShareUri(text), 'Messages');
          },
        ),
        ListTile(
          key: const Key('share-copy'),
          leading: const Icon(Icons.link, color: AppColors.turquoise),
          title: const Text('Copy link'),
          onTap: () async {
            Navigator.of(sheetContext).pop();
            await Clipboard.setData(ClipboardData(text: url));
            messenger.showSnackBar(const SnackBar(content: Text('Link copied.')));
          },
        ),
      ]),
    ),
  );
}
