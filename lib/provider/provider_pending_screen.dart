import 'package:flutter/material.dart';

import '../api/provider_profile.dart';
import '../app_colors.dart';
import '../widgets/app_logo.dart';
import 'provider_widgets.dart';

/// Shown after registering until an admin reviews the profile. Also covers a
/// rejected profile, with the reviewer's note and a way to fix and resubmit.
class ProviderPendingScreen extends StatefulWidget {
  const ProviderPendingScreen({
    super.key,
    required this.profile,
    required this.onRefresh,
    required this.onEdit,
    required this.onSignOut,
    required this.onSwitchRole,
  });

  final ProviderProfileData profile;

  /// Re-checks the profile's status on the server.
  final Future<void> Function() onRefresh;
  final VoidCallback onEdit;
  final VoidCallback onSignOut;
  final VoidCallback onSwitchRole;

  @override
  State<ProviderPendingScreen> createState() => _ProviderPendingScreenState();
}

class _ProviderPendingScreenState extends State<ProviderPendingScreen> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final rejected = profile.status == ProviderStatus.rejected;
    final accent = rejected ? const Color(0xFFBA1A1A) : const Color(0xFFB45309);
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const AppLogo(),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => value == 'role' ? widget.onSwitchRole() : widget.onSignOut(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'role', child: Text('Switch role')),
              PopupMenuItem(value: 'out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(rejected ? Icons.error_outline : Icons.hourglass_top, color: accent, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              rejected ? 'Not approved yet' : 'Pending review',
              key: const Key('review-title'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navy),
            ),
            const SizedBox(height: 8),
            Text(
              rejected
                  ? 'We could not approve your profile as it is. Update your details and send it back for another look.'
                  : "Thanks, ${profile.businessName}. We're reviewing your details and will approve you "
                      'shortly. Once approved, you can be matched with clients in your cities.',
              style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
            ),
            if (rejected && profile.reviewNote.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  profile.reviewNote,
                  key: const Key('review-note'),
                  style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.navy),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Align(alignment: Alignment.centerLeft, child: StatusPill(profile.status)),
            const SizedBox(height: 12),
            ProviderProfileCard(profile: profile),
            const SizedBox(height: 24),
            BrandButton(
              key: const Key('edit-profile'),
              label: rejected ? 'Edit and resubmit' : 'Edit details',
              outlined: !rejected,
              onPressed: widget.onEdit,
            ),
            if (!rejected) ...[
              const SizedBox(height: 12),
              BrandButton(
                key: const Key('refresh-status'),
                label: 'Check status',
                icon: Icons.refresh,
                busy: _refreshing,
                onPressed: _refresh,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
