import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../legal/legal_pages.dart';
import '../provider/provider_session.dart';
import 'delete_account.dart';

/// "Account and legal": the legal pages and Delete my account, for the provider screens (clients have the same
/// things in Settings).
class AccountAndLegalSection extends StatelessWidget {
  const AccountAndLegalSection({
    super.key,
    required this.session,
    this.openUrl = openInBrowser,
    this.afterDeleted,
  });

  final AuthSession session;
  final UrlOpener openUrl;
  final Future<void> Function(BuildContext context)? afterDeleted;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, IconData icon, VoidCallback onTap, {Key? key, bool destructive = false}) => ListTile(
          key: key,
          leading: Icon(icon, color: destructive ? const Color(0xFFBA1A1A) : AppColors.navy),
          title: Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: destructive ? const Color(0xFFBA1A1A) : AppColors.navy)),
          trailing: destructive ? null : const Icon(Icons.open_in_new, size: 18, color: AppColors.navy),
          onTap: onTap,
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Account and legal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(kRadius), boxShadow: kCardShadow),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: [
            tile('Privacy policy', Icons.privacy_tip_outlined, () => openLegalPage(context, LegalPage.privacy, open: openUrl), key: const Key('link-privacy')),
            const Divider(height: 1, indent: 16),
            tile('Terms of service', Icons.description_outlined, () => openLegalPage(context, LegalPage.terms, open: openUrl), key: const Key('link-terms')),
            const Divider(height: 1, indent: 16),
            tile('Provider agreement', Icons.handshake_outlined, () => openLegalPage(context, LegalPage.providerAgreement, open: openUrl), key: const Key('link-provider-agreement')),
            const Divider(height: 1, indent: 16),
            tile(
              'Delete my account',
              Icons.delete_outline,
              () => startDeleteAccount(context, session: session, isProvider: true, afterDeleted: afterDeleted),
              key: const Key('delete-account'),
              destructive: true,
            ),
          ]),
        ),
      ),
    ]);
  }
}
