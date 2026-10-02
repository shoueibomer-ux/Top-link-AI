import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';

/// The exact consent copy shown on this step and recorded (as `consent:
/// true`) with the request — see ApiClient.createServiceRequest /
/// provider_search.views.ServiceRequestCreateView. Never defaulted or
/// pre-checked.
const kServiceRequestConsentText =
    'I consent to Top-Link AI sharing the details of this request, including '
    'my phone number, with service providers who may be able to help.';

/// The final onboarding step: review the category, add an optional note,
/// enter a phone number, and give explicit consent — then "Continue" (see
/// OnboardingScreen) submits the request. Replaces the old static "We found
/// providers" screen now that there's no provider search to report on.
class ConfirmationStep extends StatelessWidget {
  const ConfirmationStep({
    super.key,
    required this.categoryLabel,
    required this.phoneController,
    required this.descriptionController,
    required this.consentGiven,
    required this.onConsentChanged,
  });

  final String categoryLabel;
  final TextEditingController phoneController;
  final TextEditingController descriptionController;
  final bool consentGiven;
  final ValueChanged<bool> onConsentChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(color: AppColors.turquoise, shape: BoxShape.circle),
          child: const Icon(Icons.assignment_turned_in_outlined, color: AppColors.white, size: 32),
        ),
        const SizedBox(height: 20),
        Text(
          'Review and submit your $categoryLabel request',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.navy),
        ),
        const SizedBox(height: 8),
        Text(
          "We'll share these details with providers once you submit.",
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const SizedBox(height: 24),
        _FieldLabel('Phone number'),
        const SizedBox(height: 6),
        _InputBox(
          child: TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: 'e.g. +1 780 555 0100',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _FieldLabel('Anything else to add? (optional)'),
        const SizedBox(height: 6),
        _InputBox(
          child: TextField(
            controller: descriptionController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Any extra detail that helps a provider understand the job',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _ConsentCheckbox(value: consentGiven, onChanged: onConsentChanged),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy));
  }
}

class _InputBox extends StatelessWidget {
  const _InputBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: child,
    );
  }
}

class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(kRadius), boxShadow: kCardShadow),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: value,
                onChanged: (checked) => onChanged(checked ?? false),
                activeColor: AppColors.turquoise,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    kServiceRequestConsentText,
                    style: const TextStyle(fontSize: 13, color: AppColors.navy, height: 1.4),
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
