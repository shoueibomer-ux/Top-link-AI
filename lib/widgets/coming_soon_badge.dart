import 'package:flutter/material.dart';

/// Small pill marking a service that exists but isn't open yet (see
/// catalog.Service.is_launched). Requests for it go on a waitlist. Also used
/// with a different [label] for the "Waitlisted" status on a saved request.
class ComingSoonBadge extends StatelessWidget {
  const ComingSoonBadge({super.key, this.label = 'Coming soon', this.compact = false});

  final String label;

  // Tighter padding and type for grid tiles, where space is scarce.
  final bool compact;

  static const _tint = Color(0xFFB45309);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: _tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: compact ? 9 : 11, fontWeight: FontWeight.w700, color: _tint),
      ),
    );
  }
}
