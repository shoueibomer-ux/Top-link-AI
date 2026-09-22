import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/real_provider.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import 'unlock_provider_dialog.dart';

class RealProviderCard extends StatefulWidget {
  const RealProviderCard({super.key, required this.provider, required this.category, this.onDismiss});

  final RealProvider provider;

  // Slug for the category this provider was found under — needed to call
  // ProviderUnlockView, which re-looks-up the provider's real contact
  // details server-side rather than trusting anything the client sends.
  final String category;

  // Called when the user marks this provider "not interested" — the parent
  // is responsible for removing it from whatever list it's rendering from.
  // No backend persistence yet, so a dismissal only lasts for this session.
  final VoidCallback? onDismiss;

  @override
  State<RealProviderCard> createState() => _RealProviderCardState();
}

class _RealProviderCardState extends State<RealProviderCard> {
  // Bookmarking is local-only for now — nothing backs it on the server yet.
  bool _isSaved = false;

  // A local, mutable copy — replaced in place once this provider is
  // unlocked (from the card's CTA or the details sheet), so the card and
  // any open sheet both reflect it immediately without re-searching.
  late RealProvider _provider = widget.provider;

  Future<void> _unlock(BuildContext context) async {
    final unlocked = await showUnlockProviderDialog(
      context,
      provider: _provider,
      category: widget.category,
    );
    if (unlocked != null && mounted) setState(() => _provider = unlocked);
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    // The ripple lives on a Material above the decorated Container, so the
    // card's border and background don't hide it.
    return Container(
      decoration: cardDecoration(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kCardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showDetails(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 20),
            child: _buildContent(context, provider),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, RealProvider provider) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _CardIconButton(
                icon: _isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: _isSaved ? AppColors.turquoise : AppColors.mutedText,
                tooltip: _isSaved ? 'Saved' : 'Save provider',
                onTap: () => setState(() => _isSaved = !_isSaved),
              ),
              const SizedBox(width: 4),
              _CardIconButton(
                icon: Icons.thumb_down_outlined,
                color: AppColors.mutedText,
                tooltip: 'Not interested',
                onTap: widget.onDismiss,
              ),
            ],
          ),
          // Avatar stays pinned to the top; the chevron is centred vertically
          // at the right edge, below the bookmark / not-interested buttons.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.turquoise.withValues(alpha: 0.12),
                    child: const Icon(Icons.storefront, color: AppColors.turquoise),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              provider.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _AvailabilityBadge(isAvailableNow: provider.isAvailableNow),
                        ],
                      ),
                      if (provider.rating != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, size: 14, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              '${provider.rating} (${provider.ratingCount ?? 0} reviews)',
                              style: TextStyle(fontSize: 13, color: AppColors.mutedText),
                            ),
                          ],
                        ),
                      ],
                      if (provider.phone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.phone_outlined, size: 14, color: AppColors.mutedText),
                            const SizedBox(width: 4),
                            Text(provider.phone, style: TextStyle(fontSize: 13, color: AppColors.mutedText)),
                          ],
                        ),
                      ],
                      // Full street address once unlocked; just the city
                      // (free/descriptive) before that.
                      if (provider.hasFullDetails && provider.address != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on_outlined, size: 14, color: AppColors.mutedText),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                provider.address!,
                                style: TextStyle(fontSize: 13, color: AppColors.mutedText),
                              ),
                            ),
                          ],
                        ),
                      ] else if (!provider.hasFullDetails && provider.city != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 14, color: AppColors.mutedText),
                            const SizedBox(width: 4),
                            Text(provider.city!, style: TextStyle(fontSize: 13, color: AppColors.mutedText)),
                          ],
                        ),
                      ],
                      if (provider.estimatedResponseMinutes != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.bolt, size: 14, color: AppColors.turquoise),
                            const SizedBox(width: 4),
                            Text(
                              'Usually responds within ~${provider.estimatedResponseMinutes} min',
                              style: const TextStyle(fontSize: 12, color: AppColors.turquoise, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                      if (provider.recentContactCount > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.people_outline, size: 14, color: AppColors.mutedText),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${provider.recentContactCount} ${provider.recentContactCount == 1 ? 'person has' : 'people have'} '
                                'contacted this provider this week',
                                style: TextStyle(fontSize: 12, color: AppColors.mutedText),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (!provider.hasFullDetails) ...[
                        const SizedBox(height: 8),
                        UnlockCtaButton(onTap: () => _unlock(context)),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Center(
                    child: Icon(Icons.chevron_right, color: AppColors.mutedText, size: 24),
                  ),
                ),
              ],
            ),
          ),
        ],
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kCardRadius)),
      ),
      builder: (_) => ProviderDetailsSheet(
        provider: _provider,
        category: widget.category,
        onUnlocked: (updated) {
          if (mounted) setState(() => _provider = updated);
        },
      ),
    );
  }
}

/// Full details for one provider, opened from the card's chevron / tap.
/// Website and maps links are shown as copyable text because the app has no
/// url_launcher dependency yet.
class ProviderDetailsSheet extends StatefulWidget {
  const ProviderDetailsSheet({
    super.key,
    required this.provider,
    required this.category,
    this.onUnlocked,
  });

  final RealProvider provider;
  final String category;

  // Fired the instant an unlock succeeds from inside this sheet — lets the
  // card behind it refresh immediately, independent of how/when the sheet
  // itself is eventually dismissed.
  final ValueChanged<RealProvider>? onUnlocked;

  @override
  State<ProviderDetailsSheet> createState() => _ProviderDetailsSheetState();
}

class _ProviderDetailsSheetState extends State<ProviderDetailsSheet> {
  late RealProvider _provider = widget.provider;

  Future<void> _unlock() async {
    final unlocked = await showUnlockProviderDialog(context, provider: _provider, category: widget.category);
    if (unlocked == null || !mounted) return;
    setState(() => _provider = unlocked);
    widget.onUnlocked?.call(unlocked);
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final rows = <Widget>[
      if (provider.phone.isNotEmpty) _DetailRow(icon: Icons.phone_outlined, label: 'Phone', value: provider.phone),
      if (provider.hasFullDetails && provider.address != null)
        _DetailRow(icon: Icons.location_on_outlined, label: 'Address', value: provider.address!)
      else if (provider.city != null)
        _DetailRow(icon: Icons.location_on_outlined, label: 'City', value: provider.city!),
      if (provider.website != null && provider.website!.isNotEmpty)
        _DetailRow(icon: Icons.language, label: 'Website', value: provider.website!),
      if (provider.mapsUrl != null && provider.mapsUrl!.isNotEmpty)
        _DetailRow(icon: Icons.map_outlined, label: 'Google Maps', value: provider.mapsUrl!),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    provider.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.navy),
                  ),
                ),
                const SizedBox(width: 8),
                _AvailabilityBadge(isAvailableNow: provider.isAvailableNow),
              ],
            ),
            if (provider.rating != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.star, size: 16, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    '${provider.rating} (${provider.ratingCount ?? 0} reviews)',
                    style: const TextStyle(fontSize: 14, color: AppColors.mutedText),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            ...rows,
            if (provider.estimatedResponseMinutes != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Usually responds within ~${provider.estimatedResponseMinutes} min',
                  style: const TextStyle(fontSize: 13, color: AppColors.turquoise, fontWeight: FontWeight.w600),
                ),
              ),
            if (!provider.hasFullDetails) ...[
              const SizedBox(height: 12),
              UnlockCtaButton(onTap: _unlock, expand: true),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Unlock contact — $4.99" (plus a short "or subscribe" line underneath) —
/// the one CTA that replaces every direct call/message affordance on a
/// locked card. Both call sites route through [showUnlockProviderDialog],
/// which decides server-side whether this device's subscription covers it
/// for free or a $4.99 charge is needed — this button never assumes either;
/// the subscribe option is always offered there too if payment is needed.
///
/// The label is deliberately short (previously "Unlock contact — $4.99 or
/// subscribe" overflowed its pill on narrower layouts, e.g. inside an Ask
/// AI chat bubble — see real_provider_card_test.dart's regression test).
/// [Flexible] + [TextOverflow.ellipsis] is kept as a second line of defence
/// in case of even narrower/larger-text contexts than tested.
class UnlockCtaButton extends StatelessWidget {
  const UnlockCtaButton({super.key, required this.onTap, this.expand = false});

  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.turquoise.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 14, color: AppColors.turquoise),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Unlock contact — \$4.99',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.turquoise),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final sized = expand ? SizedBox(width: double.infinity, child: button) : button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: expand ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        sized,
        const SizedBox(height: 4),
        Text(
          'or subscribe for unlimited unlocks',
          style: TextStyle(fontSize: 11, color: AppColors.mutedText),
        ),
      ],
    );
  }
}

class _DetailRow extends StatefulWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  State<_DetailRow> createState() => _DetailRowState();
}

class _DetailRowState extends State<_DetailRow> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.icon, size: 18, color: AppColors.mutedText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label, style: const TextStyle(fontSize: 12, color: AppColors.mutedText)),
                Text(widget.value, style: const TextStyle(fontSize: 14, color: AppColors.navy)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy ${widget.label.toLowerCase()}',
            icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 18, color: AppColors.turquoise),
            onPressed: _copy,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.isAvailableNow});

  final bool isAvailableNow;

  @override
  Widget build(BuildContext context) {
    final color = isAvailableNow ? AppColors.turquoise : AppColors.mutedText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            isAvailableNow ? 'Available now' : 'Busy',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _CardIconButton extends StatelessWidget {
  const _CardIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        icon: Icon(icon, size: 18, color: color),
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        splashRadius: 18,
      ),
    );
  }
}
