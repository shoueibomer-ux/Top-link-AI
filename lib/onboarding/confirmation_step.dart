import 'package:flutter/material.dart';

import '../app_colors.dart';

class ConfirmationStep extends StatelessWidget {
  const ConfirmationStep({super.key, required this.categoryLabel});

  final String categoryLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            color: AppColors.turquoise,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: AppColors.white, size: 48),
        ),
        const SizedBox(height: 32),
        const Text(
          "We found providers ready to help you in your area",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Top-rated $categoryLabel pros near you are ready to take your request.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
      ],
    );
  }
}
