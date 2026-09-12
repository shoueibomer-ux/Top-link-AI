import 'package:flutter/material.dart';

import '../app_colors.dart';

/// The full Top Link AI logo (icon + wordmark), on a light pill so its dark
/// text stays legible when placed over the navy app bar / drawer header.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 32});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Image.asset(
        'assets/images/toplinkai_logo_full.png',
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }
}
