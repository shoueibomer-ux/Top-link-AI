import 'package:flutter/material.dart';

import '../api/match_result.dart';
import '../app_colors.dart';
import '../app_styles.dart';

class ProviderCard extends StatefulWidget {
  const ProviderCard({super.key, required this.match, this.onDismiss});

  final MatchResult match;

  // Called when the user marks this provider "not interested" — the parent
  // is responsible for removing it from whatever list it's rendering from.
  // No backend persistence yet, so a dismissal only lasts for this session.
  final VoidCallback? onDismiss;

  @override
  State<ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<ProviderCard> {
  // Bookmarking is local-only for now — nothing backs it on the server yet.
  bool _isSaved = false;

  @override
  Widget build(BuildContext context) {
    final profile = widget.match.profile;
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
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.turquoise.withValues(alpha: 0.12),
                  child: Text(
                    '${widget.match.score.round()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.turquoise,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            '${profile.rating} · ${widget.match.distanceKm} km away',
                            style: TextStyle(fontSize: 13, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.navy),
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
