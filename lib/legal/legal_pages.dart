import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_config.dart';

/// The legal and account pages on the website. The app opens them in the phone's browser, so the text is always
/// the current one and is not frozen into an app release.
enum LegalPage {
  privacy('/privacy/', 'Privacy Policy'),
  terms('/terms/', 'Terms of Service'),
  providerAgreement('/provider-agreement/', 'Provider Agreement'),
  deleteAccount('/delete-account/', 'How to delete your account');

  const LegalPage(this.path, this.title);

  final String path;
  final String title;

  Uri get uri => Uri.parse(ApiConfig.siteUrl(path));
}

/// Opens a page in the browser. Tests pass a fake.
typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> openInBrowser(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens [page], and says so if the phone could not.
Future<void> openLegalPage(BuildContext context, LegalPage page, {UrlOpener open = openInBrowser}) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await open(page.uri);
  } catch (_) {
    opened = false;
  }
  if (!opened) messenger.showSnackBar(SnackBar(content: Text('Could not open ${page.title}. Check your connection and try again.')));
}
