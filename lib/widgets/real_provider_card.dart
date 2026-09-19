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
      padding: const EdgeInsets.fromLTRB(20, 10, 14, 20),
      decoration: cardDecoration(),
      child: Column(
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
                      if (provider.address != null) ...[
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
