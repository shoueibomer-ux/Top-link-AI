import 'package:flutter/material.dart';

import '../api/reviews.dart';
import '../app_colors.dart';

const _starColor = Color(0xFFF5A623);
const _emptyStarColor = Color(0xFFC3CEDA);

/// Five stars showing [rating] (whole stars), read-only.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.size = 16});

  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$rating out of 5 stars',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: i <= rating ? _starColor : _emptyStarColor),
      ]),
    );
  }
}

/// "★ 4.5 (12 reviews)", or "No reviews yet" before the first one.
class RatingLine extends StatelessWidget {
  const RatingLine({super.key, required this.rating, this.fontSize = 12, this.showEmpty = true});

  final RatingSummary rating;
  final double fontSize;

  /// When false, nothing is shown until there is at least one review.
  final bool showEmpty;

  @override
  Widget build(BuildContext context) {
    if (!rating.hasReviews) {
      if (!showEmpty) return const SizedBox.shrink();
      return Text('No reviews yet', style: TextStyle(fontSize: fontSize, color: AppColors.mutedText));
    }
    final n = rating.count;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, size: fontSize + 4, color: _starColor),
      const SizedBox(width: 2),
      Text(
        rating.average!.toStringAsFixed(1),
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: AppColors.navy),
      ),
      const SizedBox(width: 4),
      Text('($n ${n == 1 ? 'review' : 'reviews'})', style: TextStyle(fontSize: fontSize, color: AppColors.mutedText)),
    ]);
  }
}

/// Five tappable stars to choose 1-5.
class StarPicker extends StatelessWidget {
  const StarPicker({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  static const _words = ['', 'Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            key: Key('star-$i'),
            tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
            onPressed: () => onChanged(i),
            iconSize: 38,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= value ? _starColor : _emptyStarColor),
          ),
      ]),
      SizedBox(
        height: 20,
        child: Text(_words[value.clamp(0, 5)], key: const Key('star-word'), style: TextStyle(fontSize: 13, color: AppColors.mutedText)),
      ),
    ]);
  }
}
