import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/growth.dart';
import '../api/service_request.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../client/client_sign_in_screen.dart';
import '../home/home_screen.dart';
import '../messaging/push_service.dart';
import '../provider/auth_storage.dart';
import '../provider/provider_session.dart';
import '../subscription/device_id.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_logo.dart';
import '../widgets/pressable.dart';
import 'category_step.dart';
import 'confirmation_step.dart';
import 'phone_validation.dart';
import 'location_step.dart';
import 'location_validation.dart';
import 'service_category.dart';
import 'urgency_step.dart';

class OnboardingScreen extends StatefulWidget {
  /// With [initialCategory] (e.g. picked from the Home screen's search bar),
  /// the flow starts at the urgency step with that category already chosen.
  const OnboardingScreen({
    super.key,
    this.initialCategory,
    this.attribution,
    this.initialDescription = '',
    this.api,
    this.idTokenProvider,
  });

  final ServiceCategory? initialCategory;

  /// Where the person came from (an SEO page, a seasonal reminder, an invite), sent with the request.
  final RequestAttribution? attribution;

  /// Text to start the description with, e.g. "Book again" naming the provider.
  final String initialDescription;

  /// Tests pass a client backed by a fake HTTP layer and a fake Google token.
  final ApiClient? api;
  final Future<String> Function()? idTokenProvider;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _stepCount = 4;

  late final _apiClient = widget.api ?? ApiClient();
  late final _session = AuthSession(api: _apiClient);
  final _phoneController = TextEditingController();
  late final _descriptionController = TextEditingController(text: widget.initialDescription);

  late int _step = widget.initialCategory == null ? 0 : 1;
  late ServiceCategory? _selectedCategory = widget.initialCategory;
  Urgency? _selectedUrgency;
  String _location = '';
  bool _consentGiven = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Continue depends on the phone being valid, so it has to follow every keystroke.
    _phoneController.addListener(() {
      if (mounted) setState(() {});
    });
  }

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
      case 2:
        return normalizeLocation(_location) != null;
      case 3:
        return !_isSubmitting && normalizeNorthAmericanPhone(_phoneController.text) != null && _consentGiven;
      default:
        return !_isSubmitting;
    }
  }

  /// A request belongs to the account that sends it, so sign-in comes last:
  /// after all the questions, when they're ready to send. False if they decline.
  Future<bool> _ensureSignedIn() async {
    if (await AuthStorage.isLoggedIn()) return true;
    if (!mounted) return false;
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClientSignInScreen(api: _apiClient, idTokenProvider: widget.idTokenProvider),
      ),
    );
    return signedIn == true;
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
      if (!await _ensureSignedIn()) {
        if (mounted) setState(() => _isSubmitting = false);
        return;
      }
      final deviceId = await getDeviceId();
      Future<ServiceRequestSubmission> send() => _session.authorized(
            (accessToken) => _apiClient.createServiceRequest(
              accessToken: accessToken,
              deviceId: deviceId,
              category: category.slug,
              phone: normalizeNorthAmericanPhone(_phoneController.text)!,
              consent: _consentGiven,
              description: _descriptionController.text.trim(),
              urgency: urgency.apiValue,
              location: normalizeLocation(_location) ?? '',
              attribution: widget.attribution,
            ),
          );
      ServiceRequestSubmission submission;
      try {
        submission = await send();
      } on SessionExpiredException {
        // The saved login is no longer valid (the session helper has cleared it):
        // sign in again and send once more.
        if (!await _ensureSignedIn()) {
          if (mounted) setState(() => _isSubmitting = false);
          return;
        }
        submission = await send();
      }

      if (!mounted) return;
      if (submission.isWaitlisted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Coming soon'),
            content: Text(submission.message ?? kWaitlistedMessage),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK')),
            ],
          ),
        );
        if (!mounted) return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(category: category, urgency: urgency),
        ),
      );
      // Now that the first request is sent, notifications are worth asking for (once).
      unawaited(PushService.instance.askAfterFirstRequest());
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
                          location: _location,
                          onLocationChanged: (location) => setState(() => _location = location),
                        ),
                      _ => ConfirmationStep(
                          categoryLabel: _selectedCategory?.label ?? 'service',
                          phoneController: _phoneController,
                          descriptionController: _descriptionController,
                          consentGiven: _consentGiven,
                          onConsentChanged: (value) => setState(() => _consentGiven = value),
                          waitlisted: _selectedCategory?.isLaunched == false,
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
