import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../home/home_screen.dart';
import '../subscription/device_id.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_logo.dart';
import '../widgets/pressable.dart';
import 'category_step.dart';
import 'confirmation_step.dart';
import 'location_step.dart';
import 'service_category.dart';
import 'urgency_step.dart';

class OnboardingScreen extends StatefulWidget {
  /// With [initialCategory] (e.g. picked from the Home screen's search bar),
  /// the flow starts at the urgency step with that category already chosen.
  const OnboardingScreen({super.key, this.initialCategory});

  final ServiceCategory? initialCategory;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _stepCount = 4;

  final _apiClient = ApiClient();
  final _phoneController = TextEditingController();
  final _descriptionController = TextEditingController();

  late int _step = widget.initialCategory == null ? 0 : 1;
  late ServiceCategory? _selectedCategory = widget.initialCategory;
  Urgency? _selectedUrgency;
  double _lat = ApiClient.demoLat;
  double _lng = ApiClient.demoLng;
  bool _consentGiven = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _selectedCategory != null;
      case 1:
        return _selectedUrgency != null;
      case 3:
        return !_isSubmitting && _phoneController.text.trim().isNotEmpty && _consentGiven;
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
      final deviceId = await getDeviceId();
      final submission = await _apiClient.createServiceRequest(
        deviceId: deviceId,
        category: category.slug,
        phone: _phoneController.text.trim(),
        consent: _consentGiven,
        description: _descriptionController.text.trim(),
      );

      if (!mounted) return;
      if (submission.isWaitlisted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(submission.message ?? 'Coming soon in your area')),
        );
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(category: category, urgency: urgency),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit your request: $e')),
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
              const SizedBox(height: 28),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  layoutBuilder: (currentChild, previousChildren) =>
                      currentChild ?? const SizedBox.shrink(),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: switch (_step) {
                      0 => CategoryStep(
                          selected: _selectedCategory,
                          onSelect: (category) {
                            // Selection now happens from the category detail
                            // page's "Select this category" button, so it
                            // also advances straight to the urgency step
                            // rather than requiring a separate Next tap.
                            setState(() => _selectedCategory = category);
                            _onContinue();
                          },
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
                          phoneController: _phoneController,
                          descriptionController: _descriptionController,
                          consentGiven: _consentGiven,
                          onConsentChanged: (value) => setState(() => _consentGiven = value),
                        ),
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Pressable(
                enabled: _canContinue,
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _canContinue ? _onContinue : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.turquoise,
                      disabledBackgroundColor: AppColors.turquoise.withValues(alpha: 0.35),
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kRadius),
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
