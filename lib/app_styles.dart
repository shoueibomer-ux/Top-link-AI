import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared shape/elevation tokens so cards, buttons, and fields read as one
/// consistent design system rather than ad-hoc per-widget values.

const kRadius = 16.0;

/// Larger radius for the restyled cards/buttons (spec: 24-32).
const kCardRadius = 24.0;

/// White card surface with the 1.5px #EDF1F5 border from the design language.
BoxDecoration cardDecoration({Color color = AppColors.white}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(kCardRadius),
      border: Border.all(color: AppColors.cardBorder, width: 1.5),
    );

List<BoxShadow> get kCardShadow => [
      BoxShadow(
        color: AppColors.navy.withValues(alpha: 0.06),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];
