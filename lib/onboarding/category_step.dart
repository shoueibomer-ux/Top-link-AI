import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/pressable.dart';
import 'category_detail_page.dart';
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
                onSelect: () => onSelect(category),
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
    required this.onSelect,
  });

  final ServiceCategory category;
  final bool isSelected;
  final VoidCallback onSelect;

  Future<void> _openDetail(BuildContext context) async {
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CategoryDetailPage(category: category)),
    );
    if (confirmed == true) onSelect();
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
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(kRadius),
            onTap: () => _openDetail(context),
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
      ),
    );
  }
}
