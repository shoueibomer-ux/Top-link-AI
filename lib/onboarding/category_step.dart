import 'package:flutter/material.dart';

import '../app_colors.dart';
import 'service_category.dart';

class CategoryStep extends StatelessWidget {
  const CategoryStep({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final ServiceCategory? selected;
  final ValueChanged<ServiceCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What do you need help with?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pick a category to find the right providers.',
          style: TextStyle(fontSize: 14, color: AppColors.navy.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: GridView.builder(
            itemCount: serviceCategories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              final category = serviceCategories[index];
              final isSelected = category.label == selected?.label;
              return _CategoryCard(
                category: category,
                isSelected: isSelected,
                onTap: () => onSelect(category),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final ServiceCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.turquoise.withValues(alpha: 0.12) : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.turquoise : const Color(0xFFE1E8EF),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                category.icon,
                size: 30,
                color: isSelected ? AppColors.turquoise : AppColors.navy,
              ),
              const SizedBox(height: 8),
              Text(
                category.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
