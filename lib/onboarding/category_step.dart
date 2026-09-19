import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/pressable.dart';
import 'service_category.dart';
import 'service_list_page.dart';

/// First step of onboarding — the "professional categories page". Shows the
/// admin-managed top-level groups (Trades & Professional Services, Home
/// Services, etc. — see catalog.Category); tapping one drills into
/// ServiceListPage for that group's services. Falls back to the static
/// 9-category list (rendered as a single implicit group) if the dynamic
/// catalog hasn't loaded yet or the fetch fails, so this screen never blocks
/// on the network.
class CategoryStep extends StatefulWidget {
  const CategoryStep({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final ServiceCategory? selected;
  final ValueChanged<ServiceCategory> onSelect;

  @override
  State<CategoryStep> createState() => _CategoryStepState();
}

class _CategoryStepState extends State<CategoryStep> {
  @override
  void initState() {
    super.initState();
    loadCatalogFromApi().then((_) {
      if (mounted) setState(() {});
    });
  }

  List<ServiceCategoryGroup> get _groups {
    if (serviceCategoryGroups.isNotEmpty) return serviceCategoryGroups;
    // Dynamic catalog not loaded yet — show the static list as one group so
    // the grid always has something to render immediately.
    return [
      ServiceCategoryGroup(
        label: 'All categories',
        icon: Icons.category,
        slug: 'all',
        services: serviceCategories,
      ),
    ];
  }

  Future<void> _openGroup(ServiceCategoryGroup group) async {
    final service = await Navigator.of(context).push<ServiceCategory>(
      MaterialPageRoute(builder: (_) => ServiceListPage(group: group)),
    );
    if (service != null) widget.onSelect(service);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
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
          'Pick a category to see the services we offer.',
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const SizedBox(height: 28),
        Expanded(
          child: GridView.builder(
            itemCount: groups.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              final group = groups[index];
              final isSelected = group.services.any((s) => s.label == widget.selected?.label);
              return _GroupCard(
                group: group,
                isSelected: isSelected,
                onTap: () => _openGroup(group),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.isSelected, required this.onTap});

  final ServiceCategoryGroup group;
  final bool isSelected;
  final VoidCallback onTap;

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
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    group.icon,
                    size: 30,
                    color: isSelected ? AppColors.turquoise : AppColors.navy,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    group.label,
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
