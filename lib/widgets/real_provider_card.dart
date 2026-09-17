import 'package:flutter/material.dart';

import '../api/real_provider.dart';
import '../app_colors.dart';
import '../app_styles.dart';

class RealProviderCard extends StatefulWidget {
  const RealProviderCard({super.key, required this.provider, this.onDismiss});

  final RealProvider provider;

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

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _CardIconButton(
                icon: _isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: _isSaved ? AppColors.turquoise : AppColors.muted,
                tooltip: _isSaved ? 'Saved' : 'Save provider',
                onTap: () => setState(() => _isSaved = !_isSaved),
              ),
              const SizedBox(width: 4),
              _CardIconButton(
                icon: Icons.thumb_down_outlined,
                color: AppColors.muted,
                tooltip: 'Not interested',
                onTap: widget.onDismiss,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.turquoise.withValues(alpha: 0.12),
                  child: const Icon(Icons.storefront, color: AppColors.turquoise),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                      if (provider.rating != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, size: 14, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              '${provider.rating} (${provider.ratingCount ?? 0} reviews)',
                              style: TextStyle(fontSize: 13, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ],
                      if (provider.phone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.phone_outlined, size: 14, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Text(provider.phone, style: TextStyle(fontSize: 13, color: AppColors.muted)),
                          ],
                        ),
                      ],
                      if (provider.address != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on_outlined, size: 14, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                provider.address!,
                                style: TextStyle(fontSize: 13, color: AppColors.muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (!provider.hasFullDetails) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Subscribe to see full contact details',
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.turquoise),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
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
