import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/provider_profile.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../onboarding/phone_validation.dart';
import '../onboarding/service_category.dart';
import '../widgets/app_logo.dart';
import 'provider_session.dart';
import 'provider_widgets.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// The provider registration form, also used to edit an existing profile.
/// Saving a new profile sends it for review; saving edits keeps its status
/// (except a rejected profile, which goes back for review).
class ProviderRegistrationScreen extends StatefulWidget {
  const ProviderRegistrationScreen({
    super.key,
    required this.session,
    required this.onSaved,
    required this.onSessionExpired,
    this.initial,
    this.defaultEmail = '',
    this.onCancel,
  });

  final ProviderSession session;
  final ValueChanged<ProviderProfileData> onSaved;
  final VoidCallback onSessionExpired;
  final ProviderProfileData? initial;

  /// Pre-fills the contact email for a new registration (their Google email).
  final String defaultEmail;
  final VoidCallback? onCancel;

  bool get isEditing => initial != null;

  @override
  State<ProviderRegistrationScreen> createState() =>
      _ProviderRegistrationScreenState();
}

class _ProviderRegistrationScreenState
    extends State<ProviderRegistrationScreen> {
  late final _name = TextEditingController(
    text: widget.initial?.businessName ?? '',
  );
  late final _phone = TextEditingController(text: widget.initial?.phone ?? '');
  late final _email = TextEditingController(
    text: widget.initial?.email ?? widget.defaultEmail,
  );
  late final _bio = TextEditingController(text: widget.initial?.bio ?? '');
  late final Set<String> _categories = {...?widget.initial?.categories};
  late final Set<String> _cities = {...?widget.initial?.cities};

  bool _submitted = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final controller in [_name, _phone, _email, _bio]) {
      controller.addListener(() {
        if (mounted) setState(() {});
      });
    }
    loadCatalogFromApi().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final controller in [_name, _phone, _email, _bio]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? get _nameError =>
      _name.text.trim().isEmpty ? 'Enter your business name.' : null;

  String? get _phoneError {
    if (_phone.text.trim().isEmpty) {
      return _submitted ? 'Enter a phone number.' : null;
    }
    return normalizeNorthAmericanPhone(_phone.text) == null
        ? kInvalidPhoneMessage
        : null;
  }

  String? get _emailError => _emailPattern.hasMatch(_email.text.trim())
      ? null
      : 'Enter a valid email address.';
  String? get _categoryError =>
      _categories.isEmpty ? 'Choose at least one service.' : null;
  String? get _cityError =>
      _cities.isEmpty ? 'Choose at least one city.' : null;

  bool get _valid =>
      _nameError == null &&
      _phoneError == null &&
      _phone.text.trim().isNotEmpty &&
      _emailError == null &&
      _categoryError == null &&
      _cityError == null;

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!_valid) return;
    setState(() => _saving = true);
    final data = ProviderProfileData(
      businessName: _name.text.trim(),
      phone: normalizeNorthAmericanPhone(_phone.text)!,
      email: _email.text.trim(),
      categories: _categories.toList(),
      cities: [
        for (final city in kProviderCities)
          if (_cities.contains(city)) city,
      ],
      bio: _bio.text.trim(),
    );
    try {
      final saved = await widget.session.authorized(
        (access) => widget.isEditing
            ? widget.session.api.updateMyProviderProfile(access, data)
            : widget.session.api.registerProviderProfile(access, data),
      );
      if (!mounted) return;
      widget.onSaved(saved);
    } on SessionExpiredException {
      if (mounted) widget.onSessionExpired();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not reach the server. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<ServiceCategoryGroup> get _groups {
    if (serviceCategoryGroups.isNotEmpty) return serviceCategoryGroups;
    return [
      ServiceCategoryGroup(
        label: 'Services',
        icon: Icons.category,
        slug: 'all',
        services: serviceCategories,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final showErrors = _submitted;
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const AppLogo(),
        leading: widget.onCancel == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _saving ? null : widget.onCancel,
              ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.isEditing ? 'Edit your profile' : 'Register your business',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isEditing ? 'Changes are saved straight away.' : 'Tell us about your business. We review every provider before they are matched with clients.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 24),
            _Field(
              fieldKey: const Key('field-business-name'),
              label: 'Business name',
              controller: _name,
              error: showErrors ? _nameError : null,
              textCapitalization: TextCapitalization.words,
            ),
            _Field(
              fieldKey: const Key('field-phone'),
              label: 'Phone number',
              hint: 'e.g. 780 555 0100',
              controller: _phone,
              error: _phoneError,
              errorKey: const Key('phone-error'),
              keyboardType: TextInputType.phone,
            ),
            _Field(
              fieldKey: const Key('field-email'),
              label: 'Contact email',
              controller: _email,
              error: showErrors ? _emailError : null,
              keyboardType: TextInputType.emailAddress,
            ),
            const _Label('Services you offer'),
            for (final group in _groups)
              _ServiceGroup(
                group: group,
                selected: _categories,
                onToggle: _toggleCategory,
                startExpanded: _groups.length == 1,
              ),
            if (showErrors && _categoryError != null)
              _ErrorText(_categoryError!, key: const Key('category-error')),
            const SizedBox(height: 18),
            const _Label('Cities you serve'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final city in kProviderCities)
                  FilterChip(
                    key: Key('city-$city'),
                    label: Text(city),
                    selected: _cities.contains(city),
                    selectedColor: AppColors.turquoise.withValues(alpha: 0.25),
                    checkmarkColor: AppColors.navy,
                    onSelected: (on) => setState(
                      () => on ? _cities.add(city) : _cities.remove(city),
                    ),
                  ),
              ],
            ),
            if (showErrors && _cityError != null)
              _ErrorText(_cityError!, key: const Key('city-error')),
            const SizedBox(height: 18),
            _Field(
              fieldKey: const Key('field-bio'),
              label: 'About your business (optional)',
              hint: 'Experience, licences, what makes you different',
              controller: _bio,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
            ),
            if (_error != null) ...[
              _ErrorText(_error!, key: const Key('save-error')),
              const SizedBox(height: 12),
            ],
            BrandButton(
              label: widget.isEditing ? 'Save changes' : 'Submit for review',
              busy: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleCategory(String slug, bool on) =>
      setState(() => on ? _categories.add(slug) : _categories.remove(slug));
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.navy,
      ),
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 2),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: Color(0xFFBA1A1A)),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.fieldKey,
    required this.label,
    required this.controller,
    this.hint,
    this.error,
    this.errorKey,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? error;
  final Key? errorKey;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? minLines;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(label),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(kRadius),
              boxShadow: kCardShadow,
            ),
            child: TextField(
              key: fieldKey,
              controller: controller,
              keyboardType: keyboardType,
              textCapitalization: textCapitalization,
              minLines: minLines,
              maxLines: maxLines,
              maxLength: maxLength,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ),
          if (error != null) _ErrorText(error!, key: errorKey),
        ],
      ),
    );
  }
}

class _ServiceGroup extends StatelessWidget {
  const _ServiceGroup({
    required this.group,
    required this.selected,
    required this.onToggle,
    required this.startExpanded,
  });

  final ServiceCategoryGroup group;
  final Set<String> selected;
  final void Function(String slug, bool on) onToggle;

  // With a single group (before the sector list has loaded) there's nothing to
  // browse, so show its services straight away.
  final bool startExpanded;

  @override
  Widget build(BuildContext context) {
    final chosen = group.services
        .where((s) => selected.contains(s.slug))
        .length;
    // The shadow lives on an outer box and the white fill on a Material, so the
    // tile's ink and background are painted by the Material it sits on.
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('group-${group.slug}'),
            initiallyExpanded: startExpanded || chosen > 0,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            title: Text(
              group.label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
            subtitle: chosen == 0
                ? null
                : Text(
                    '$chosen selected',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.turquoise,
                    ),
                  ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final service in group.services)
                    FilterChip(
                      key: Key('service-${service.slug}'),
                      label: Text(service.label),
                      selected: selected.contains(service.slug),
                      selectedColor: AppColors.turquoise.withValues(
                        alpha: 0.25,
                      ),
                      checkmarkColor: AppColors.navy,
                      onSelected: (on) => onToggle(service.slug, on),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
