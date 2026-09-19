import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/provider_onboarding.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../onboarding/service_category.dart';
import 'provider_id.dart';

// Mirrors provider_search.services.CITIES.
const _cities = ['Edmonton', 'Calgary', 'Fort McMurray', 'Red Deer'];

/// Structured provider sign-up: 5 independently-saveable sections (Personal
/// Info, Services Offered, Service Area, Credentials, Photos) tracked with a
/// visible completion percentage — each section persists to the backend as
/// soon as it's saved, so a provider can finish the wizard across sessions
/// (see provider_search.models.ProviderOnboarding).
class ProviderOnboardingScreen extends StatefulWidget {
  const ProviderOnboardingScreen({super.key});

  @override
  State<ProviderOnboardingScreen> createState() => _ProviderOnboardingScreenState();
}

class _ProviderOnboardingScreenState extends State<ProviderOnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _apiClient = ApiClient();
  late final TabController _tabController =
      TabController(length: OnboardingSection.all.length, vsync: this);

  String? _providerId;
  ProviderOnboarding? _onboarding;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final providerId = await getProviderId();
      final onboarding = await _apiClient.getProviderOnboarding(providerId);
      if (mounted) {
        setState(() {
          _providerId = providerId;
          _onboarding = onboarding;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSectionSaved(ProviderOnboarding updated) {
    setState(() => _onboarding = updated);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = _onboarding;
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Provider Sign-Up'),
        bottom: onboarding == null
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: AppColors.turquoise,
                labelColor: AppColors.white,
                unselectedLabelColor: AppColors.white.withValues(alpha: 0.7),
                tabs: [
                  for (final section in OnboardingSection.all)
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onboarding.isSectionComplete(section)) ...[
                            const Icon(Icons.check_circle, size: 15, color: AppColors.turquoise),
                            const SizedBox(width: 6),
                          ],
                          Text(OnboardingSection.label(section)),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.turquoise))
            : _loadFailed || onboarding == null || _providerId == null
                ? _ErrorState(onRetry: _load)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Profile completeness',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy),
                                ),
                                Text(
                                  '${onboarding.completionPercentage}%',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.turquoise,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: onboarding.completionPercentage / 100,
                                minHeight: 8,
                                backgroundColor: AppColors.white,
                                valueColor: const AlwaysStoppedAnimation(AppColors.turquoise),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _PersonalInfoTab(
                              key: ValueKey('personal_${onboarding.updatedAtKey}'),
                              apiClient: _apiClient,
                              providerId: _providerId!,
                              onboarding: onboarding,
                              onSaved: _onSectionSaved,
                            ),
                            _ServicesTab(
                              key: ValueKey('services_${onboarding.updatedAtKey}'),
                              apiClient: _apiClient,
                              providerId: _providerId!,
                              onboarding: onboarding,
                              onSaved: _onSectionSaved,
                            ),
                            _ServiceAreaTab(
                              key: ValueKey('area_${onboarding.updatedAtKey}'),
                              apiClient: _apiClient,
                              providerId: _providerId!,
                              onboarding: onboarding,
                              onSaved: _onSectionSaved,
                            ),
                            _CredentialsTab(
                              key: ValueKey('credentials_${onboarding.updatedAtKey}'),
                              apiClient: _apiClient,
                              providerId: _providerId!,
                              onboarding: onboarding,
                              onSaved: _onSectionSaved,
                            ),
                            _PhotosTab(
                              key: ValueKey('photos_${onboarding.updatedAtKey}'),
                              apiClient: _apiClient,
                              providerId: _providerId!,
                              onboarding: onboarding,
                              onSaved: _onSectionSaved,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

extension on ProviderOnboarding {
  // Cheap way to force each tab's controllers to reseed only when the
  // record actually changes (e.g. after a save), not on every rebuild.
  String get updatedAtKey => '$fullName|$phone|$email|$services|$city|$yearsExperience|$isInsured|$photoUrls';
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load onboarding progress.', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry', style: TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared scaffold for every section tab: scrollable form fields, then a
/// full-width Save button pinned to the bottom.
class _SectionForm extends StatelessWidget {
  const _SectionForm({required this.children, required this.saving, required this.onSave});

  final List<Widget> children;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            children: children,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: saving ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.turquoise,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
              ),
              child: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                    )
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(kRadius),
              boxShadow: kCardShadow,
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _runSave({
  required BuildContext context,
  required ValueChanged<bool> setSaving,
  required Future<ProviderOnboarding> Function() save,
  required ValueChanged<ProviderOnboarding> onSaved,
}) async {
  setSaving(true);
  try {
    final updated = await save();
    onSaved(updated);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save — try again.')),
      );
    }
  } finally {
    setSaving(false);
  }
}

class _PersonalInfoTab extends StatefulWidget {
  const _PersonalInfoTab({
    super.key,
    required this.apiClient,
    required this.providerId,
    required this.onboarding,
    required this.onSaved,
  });

  final ApiClient apiClient;
  final String providerId;
  final ProviderOnboarding onboarding;
  final ValueChanged<ProviderOnboarding> onSaved;

  @override
  State<_PersonalInfoTab> createState() => _PersonalInfoTabState();
}

class _PersonalInfoTabState extends State<_PersonalInfoTab> {
  late final _nameController = TextEditingController(text: widget.onboarding.fullName);
  late final _phoneController = TextEditingController(text: widget.onboarding.phone);
  late final _emailController = TextEditingController(text: widget.onboarding.email);
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SectionForm(
      saving: _saving,
      onSave: () => _runSave(
        context: context,
        setSaving: (v) => setState(() => _saving = v),
        onSaved: widget.onSaved,
        save: () => widget.apiClient.saveProviderOnboardingSection(
          providerId: widget.providerId,
          section: OnboardingSection.personalInfo,
          fields: {
            'full_name': _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'email': _emailController.text.trim(),
          },
        ),
      ),
      children: [
        _LabeledField(label: 'Full name', controller: _nameController),
        _LabeledField(label: 'Phone', controller: _phoneController, keyboardType: TextInputType.phone),
        _LabeledField(label: 'Email', controller: _emailController, keyboardType: TextInputType.emailAddress),
      ],
    );
  }
}

class _ServicesTab extends StatefulWidget {
  const _ServicesTab({
    super.key,
    required this.apiClient,
    required this.providerId,
    required this.onboarding,
    required this.onSaved,
  });

  final ApiClient apiClient;
  final String providerId;
  final ProviderOnboarding onboarding;
  final ValueChanged<ProviderOnboarding> onSaved;

  @override
  State<_ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<_ServicesTab> {
  late final Set<String> _selected = widget.onboarding.services.toSet();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return _SectionForm(
      saving: _saving,
      onSave: () => _runSave(
        context: context,
        setSaving: (v) => setState(() => _saving = v),
        onSaved: widget.onSaved,
        save: () => widget.apiClient.saveProviderOnboardingSection(
          providerId: widget.providerId,
          section: OnboardingSection.services,
          fields: {'services': _selected.toList()},
        ),
      ),
      children: [
        Text(
          'Select every category this business offers.',
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in serviceCategories)
              _SelectableChip(
                label: category.label,
                selected: _selected.contains(category.slug),
                onTap: () => setState(() {
                  if (!_selected.remove(category.slug)) _selected.add(category.slug);
                }),
              ),
          ],
        ),
      ],
    );
  }
}

class _ServiceAreaTab extends StatefulWidget {
  const _ServiceAreaTab({
    super.key,
    required this.apiClient,
    required this.providerId,
    required this.onboarding,
    required this.onSaved,
  });

  final ApiClient apiClient;
  final String providerId;
  final ProviderOnboarding onboarding;
  final ValueChanged<ProviderOnboarding> onSaved;

  @override
  State<_ServiceAreaTab> createState() => _ServiceAreaTabState();
}

class _ServiceAreaTabState extends State<_ServiceAreaTab> {
  String? _city;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _city = widget.onboarding.city.isEmpty ? null : widget.onboarding.city;
  }

  @override
  Widget build(BuildContext context) {
    return _SectionForm(
      saving: _saving,
      onSave: () => _runSave(
        context: context,
        setSaving: (v) => setState(() => _saving = v),
        onSaved: widget.onSaved,
        save: () => widget.apiClient.saveProviderOnboardingSection(
          providerId: widget.providerId,
          section: OnboardingSection.serviceArea,
          fields: {'city': _city ?? ''},
        ),
      ),
      children: [
        const Text('City', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: kCardShadow,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text('Choose a city'),
              value: _city,
              items: [for (final city in _cities) DropdownMenuItem(value: city, child: Text(city))],
              onChanged: (value) => setState(() => _city = value),
            ),
          ),
        ),
      ],
    );
  }
}

class _CredentialsTab extends StatefulWidget {
  const _CredentialsTab({
    super.key,
    required this.apiClient,
    required this.providerId,
    required this.onboarding,
    required this.onSaved,
  });

  final ApiClient apiClient;
  final String providerId;
  final ProviderOnboarding onboarding;
  final ValueChanged<ProviderOnboarding> onSaved;

  @override
  State<_CredentialsTab> createState() => _CredentialsTabState();
}

class _CredentialsTabState extends State<_CredentialsTab> {
  late final _yearsController =
      TextEditingController(text: widget.onboarding.yearsExperience?.toString() ?? '');
  late bool _insured = widget.onboarding.isInsured;
  bool _saving = false;

  @override
  void dispose() {
    _yearsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SectionForm(
      saving: _saving,
      onSave: () => _runSave(
        context: context,
        setSaving: (v) => setState(() => _saving = v),
        onSaved: widget.onSaved,
        save: () => widget.apiClient.saveProviderOnboardingSection(
          providerId: widget.providerId,
          section: OnboardingSection.credentials,
          fields: {
            'years_experience': int.tryParse(_yearsController.text.trim()),
            'is_insured': _insured,
          },
        ),
      ),
      children: [
        _LabeledField(
          label: 'Years of experience',
          controller: _yearsController,
          keyboardType: TextInputType.number,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: kCardShadow,
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Insured', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w500)),
            value: _insured,
            activeThumbColor: AppColors.turquoise,
            onChanged: (value) => setState(() => _insured = value),
          ),
        ),
      ],
    );
  }
}

class _PhotosTab extends StatefulWidget {
  const _PhotosTab({
    super.key,
    required this.apiClient,
    required this.providerId,
    required this.onboarding,
    required this.onSaved,
  });

  final ApiClient apiClient;
  final String providerId;
  final ProviderOnboarding onboarding;
  final ValueChanged<ProviderOnboarding> onSaved;

  @override
  State<_PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends State<_PhotosTab> {
  late final List<String> _urls = List.of(widget.onboarding.photoUrls);
  final _urlController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _addUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _urls.add(url);
      _urlController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SectionForm(
      saving: _saving,
      onSave: () => _runSave(
        context: context,
        setSaving: (v) => setState(() => _saving = v),
        onSaved: widget.onSaved,
        save: () => widget.apiClient.saveProviderOnboardingSection(
          providerId: widget.providerId,
          section: OnboardingSection.photos,
          fields: {'photo_urls': _urls},
        ),
      ),
      children: [
        Text(
          "Paste links to photos hosted elsewhere — there's no file upload in this demo.",
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(kRadius),
                  boxShadow: kCardShadow,
                ),
                child: TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: 'https://…',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onSubmitted: (_) => _addUrl(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: AppColors.turquoise,
              borderRadius: BorderRadius.circular(kRadius),
              child: InkWell(
                borderRadius: BorderRadius.circular(kRadius),
                onTap: _addUrl,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Icon(Icons.add, color: AppColors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final url in _urls)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(kRadius),
              boxShadow: kCardShadow,
            ),
            child: Row(
              children: [
                const Icon(Icons.image_outlined, size: 18, color: AppColors.turquoise),
                const SizedBox(width: 10),
                Expanded(child: Text(url, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.navy))),
                InkWell(
                  onTap: () => setState(() => _urls.remove(url)),
                  child: Icon(Icons.close, size: 18, color: AppColors.muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.turquoise : AppColors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: selected ? null : kCardShadow,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.white : AppColors.navy,
            ),
          ),
        ),
      ),
    );
  }
}
