import 'package:flutter/material.dart';

import '../app_colors.dart';

enum Urgency {
  today('Today', 'Need someone as soon as possible', Icons.bolt),
  thisWeek('This week', 'Flexible within the next few days', Icons.calendar_today),
  exploring('Just exploring', 'Comparing options for now', Icons.search);

  const Urgency(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

class UrgencyStep extends StatelessWidget {
  const UrgencyStep({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final Urgency? selected;
  final ValueChanged<Urgency> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How soon do you need this done?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This helps us prioritize the right providers for you.',
          style: TextStyle(fontSize: 14, color: AppColors.navy.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 24),
        for (final urgency in Urgency.values) ...[
          _UrgencyTile(
            urgency: urgency,
            isSelected: urgency == selected,
            onTap: () => onSelect(urgency),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _UrgencyTile extends StatelessWidget {
  const _UrgencyTile({
    required this.urgency,
    required this.isSelected,
    required this.onTap,
  });

  final Urgency urgency;
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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.turquoise : const Color(0xFFE1E8EF),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isSelected
                    ? AppColors.turquoise
                    : AppColors.lightBackground,
                child: Icon(
                  urgency.icon,
                  color: isSelected ? AppColors.white : AppColors.navy,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      urgency.label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      urgency.description,
                      style: TextStyle(fontSize: 13, color: AppColors.navy.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: AppColors.turquoise),
            ],
          ),
        ),
      ),
    );
  }
}
