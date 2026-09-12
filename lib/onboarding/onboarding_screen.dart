import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_colors.dart';
import '../home/home_screen.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_logo.dart';
import 'category_step.dart';
import 'confirmation_step.dart';
import 'location_step.dart';
import 'service_category.dart';
import 'urgency_step.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _stepCount = 4;

  final _apiClient = ApiClient();

  int _step = 0;
  ServiceCategory? _selectedCategory;
  Urgency? _selectedUrgency;
  double _lat = ApiClient.demoLat;
  double _lng = ApiClient.demoLng;
  bool _isSubmitting = false;

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _selectedCategory != null;
      case 1:
        return _selectedUrgency != null;
      default:
        return !_isSubmitting;
    }
  }

  Future<void> _onContinue() async {
    if (!_canContinue) return;
    if (_step < _stepCount - 1) {
      setState(() => _step++);
      return;
    }

    final category = _selectedCategory!;
    final urgency = _selectedUrgency!;
    setState(() => _isSubmitting = true);

    try {
      final requestText =
          'Looking for a ${category.label} provider. Urgency: ${urgency.label}.';
      final requesterId = await _apiClient.createAnonymousProfile(
        description: requestText,
        lat: _lat,
        lng: _lng,
      );
      final matches = await _apiClient.requestMatch(
        requesterId: requesterId,
        requestText: requestText,
        lat: _lat,
        lng: _lng,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            category: category,
            urgency: urgency,
            matches: matches,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reach the matching service: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const AppLogo()),
      drawer: const AppDrawer(),
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
                  2 => LocationStep(
                      lat: _lat,
                      lng: _lng,
                      onLocationChanged: (location) => setState(() {
                        _lat = location.lat;
                        _lng = location.lng;
                      }),
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
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(AppColors.white),
                          ),
                        )
                      : Text(
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
