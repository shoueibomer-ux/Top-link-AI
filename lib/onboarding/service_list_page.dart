import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/pressable.dart';
import 'category_detail_page.dart';
import 'service_category.dart';

/// Second step of the categories-page drill-down: shows the services inside
/// one group (e.g. "Home Services" -> Cleaning, Moving, Furniture Assembly,
/// Home Repair). Pushed when a group card is tapped on CategoryStep. Pops
/// with the selected ServiceCategory once the user confirms a service on
/// CategoryDetailPage, or with no result on back navigation — mirrors the
/// pop-chaining CategoryStep's own _CategoryCard already used before this
/// group layer existed.
class ServiceListPage extends StatelessWidget {
  const ServiceListPage({super.key, required this.group});

  final ServiceCategoryGroup group;

  Future<void> _openDetail(BuildContext context, ServiceCategory service) async {
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CategoryDetailPage(category: service)),
    );
    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop(service);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: Text(group.label)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GridView.builder(
            itemCount: group.services.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              final service = group.services[index];
              return _ServiceTile(
                service: service,
                onTap: () => _openDetail(context, service),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.onTap});

  final ServiceCategory service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(kRadius),
          boxShadow: kCardShadow,
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
                  Icon(service.icon, size: 30, color: AppColors.navy),
                  const SizedBox(height: 10),
                  Text(
                    service.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.navy),
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
