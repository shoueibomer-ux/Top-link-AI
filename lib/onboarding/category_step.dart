import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/pressable.dart';
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
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pick a category to find the right providers.',
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const SizedBox(height: 28),
        Expanded(
          child: GridView.builder(
            itemCount: serviceCategories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
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

  void _showInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.turquoise.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(category.icon, color: AppColors.turquoise),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      category.label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                category.description,
                style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.navy),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? AppColors.turquoise.withValues(alpha: 0.12) : AppColors.white,
          borderRadius: BorderRadius.circular(kRadius),
          boxShadow: kCardShadow,
          border: isSelected ? Border.all(color: AppColors.turquoise, width: 2) : null,
        ),
        child: Stack(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(kRadius),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        category.icon,
                        size: 30,
                        color: isSelected ? AppColors.turquoise : AppColors.navy,
                      ),
                      const SizedBox(height: 10),
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
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _showInfo(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.white,
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(BorderSide(color: Color(0xFFE1E8EF))),
                    ),
                    child: const Icon(Icons.info_outline, size: 14, color: AppColors.navy),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
