import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../home/home_screen.dart';
import 'category_step.dart';
import 'confirmation_step.dart';
import 'service_category.dart';
import 'urgency_step.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _stepCount = 3;

  int _step = 0;
  ServiceCategory? _selectedCategory;
  Urgency? _selectedUrgency;

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _selectedCategory != null;
      case 1:
        return _selectedUrgency != null;
      default:
        return true;
    }
  }

  void _onContinue() {
    if (!_canContinue) return;
    if (_step < _stepCount - 1) {
      setState(() => _step++);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            category: _selectedCategory!,
            urgency: _selectedUrgency!,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _StepProgress(currentStep: _step, stepCount: _stepCount),
              const SizedBox(height: 24),
              Expanded(
                child: switch (_step) {
                  0 => CategoryStep(
                      selected: _selectedCategory,
                      onSelect: (category) =>
                          setState(() => _selectedCategory = category),
                    ),
                  1 => UrgencyStep(
                      selected: _selectedUrgency,
                      onSelect: (urgency) =>
                          setState(() => _selectedUrgency = urgency),
                    ),
                  _ => ConfirmationStep(
                      categoryLabel: _selectedCategory?.label ?? 'service',
                    ),
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canContinue ? _onContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.turquoise,
                    disabledBackgroundColor: AppColors.turquoise.withValues(alpha: 0.35),
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _step == _stepCount - 1 ? 'Continue' : 'Next',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.currentStep, required this.stepCount});

  final int currentStep;
  final int stepCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < stepCount; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i <= currentStep
                    ? AppColors.turquoise
                    : const Color(0xFFE1E8EF),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
