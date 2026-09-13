import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared shape/elevation tokens so cards, buttons, and fields read as one
/// consistent design system rather than ad-hoc per-widget values.

const kRadius = 16.0;

List<BoxShadow> get kCardShadow => [
      BoxShadow(
        color: AppColors.navy.withValues(alpha: 0.06),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];
