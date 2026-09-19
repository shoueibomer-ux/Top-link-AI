import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/auth_models.dart';
import '../app_colors.dart';
import '../app_styles.dart';
import '../onboarding/service_category.dart';
import 'auth_storage.dart';
import 'provider_auth_screen.dart';

// Mirrors provider_search.services.CITIES.
const _cities = ['Edmonton', 'Calgary', 'Fort McMurray', 'Red Deer'];

/// The authenticated provider's business profile — accounts.ProviderBusinessProfile,
/// the ONE permanent provider identity per the marketplace build plan.
/// Replaces the self-issued-UUID onboarding wizard as where a provider's
/// real data lives; the wizard itself is untouched and still reachable.
class ProviderBusinessProfileScreen extends StatefulWidget {
  const ProviderBusinessProfileScreen({super.key});

  @override
  State<ProviderBusinessProfileScreen> createState() => _ProviderBusinessProfileScreenState();
}

class _ProviderBusinessProfileScreenState extends State<ProviderBusinessProfileScreen> {
  final _apiClient = ApiClient();

  String? _accessToken;
  ProviderBusinessProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late final _businessNameController = TextEditingController();
  late final _descriptionController = TextEditingController();
  late final _phoneController = TextEditingController();
  late final _teamSizeController = TextEditingController();
  late final _yearsExperienceController = TextEditingController();
  late final _serviceRadiusController = TextEditingController();
  late final _languagesController = TextEditingController();
  late final _equipmentController = TextEditingController();
  late final _certificationsController = TextEditingController();
  final _photoUrlController = TextEditingController();

  Set<String> _selectedCategories = {};
  String? _city;
  String _providerType = ProviderType.individual;
  bool _isInsured = false;
  bool _isAvailableNow = true;
  List<String> _photoUrls = [];

  List<KnownProvider> _knownProviders = [];
  KnownProvider? _selectedClaim;
  String? _claimedPlaceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _teamSizeController.dispose();
    _yearsExperienceController.dispose();
    _serviceRadiusController.dispose();
    _languagesController.dispose();
    _equipmentController.dispose();
    _certificationsController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final token = await AuthStorage.getAccessToken();
    if (token == null) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProviderAuthScreen()),
        );
      }
      return;
    }

    try {
      final profile = await _apiClient.getProviderBusinessProfile(token);
      final known = await _apiClient.getKnownProviders();
      if (!mounted) return;
      setState(() {
        _accessToken = token;
        _profile = profile;
        _knownProviders = known;
        _applyProfile(profile);
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your business profile.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyProfile(ProviderBusinessProfile profile) {
    _businessNameController.text = profile.businessName;
    _descriptionController.text = profile.description;
    _phoneController.text = profile.phone;
    _teamSizeController.text = profile.teamSize?.toString() ?? '';
    _yearsExperienceController.text = profile.yearsExperience?.toString() ?? '';
    _serviceRadiusController.text = profile.serviceRadiusKm?.toString() ?? '';
    _languagesController.text = profile.languages.join(', ');
    _equipmentController.text = profile.equipment.join(', ');
    _certificationsController.text = profile.certifications.join(', ');
    _selectedCategories = profile.categories.toSet();
    _city = profile.city.isEmpty ? null : profile.city;
    _providerType = profile.providerType;
    _isInsured = profile.isInsured;
    _isAvailableNow = profile.isAvailableNow;
    _photoUrls = List.of(profile.photoUrls);
    _claimedPlaceId = profile.placeId;
  }

  List<String> _splitCommaList(String text) =>
      text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Future<void> _save() async {
    if (_accessToken == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updated = await _apiClient.updateProviderBusinessProfile(
        accessToken: _accessToken!,
        fields: {
          'business_name': _businessNameController.text.trim(),
          'description': _descriptionController.text.trim(),
          'categories': _selectedCategories.toList(),
          'city': _city ?? '',
          'phone': _phoneController.text.trim(),
          'provider_type': _providerType,
          'team_size': int.tryParse(_teamSizeController.text.trim()),
          'years_experience': int.tryParse(_yearsExperienceController.text.trim()),
          'is_insured': _isInsured,
          'service_radius_km': double.tryParse(_serviceRadiusController.text.trim()),
          'languages': _splitCommaList(_languagesController.text),
          'equipment': _splitCommaList(_equipmentController.text),
          'certifications': _splitCommaList(_certificationsController.text),
          'photo_urls': _photoUrls,
          'is_available_now': _isAvailableNow,
        },
      );
      if (!mounted) return;
      setState(() => _profile = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save your profile — try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _claimListing() async {
    if (_accessToken == null || _selectedClaim == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _apiClient.updateProviderBusinessProfile(
        accessToken: _accessToken!,
        fields: {'place_id': _selectedClaim!.placeId},
      );
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _claimedPlaceId = updated.placeId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Claimed "${_selectedClaim!.name}".')),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not claim that listing — try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Business Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              await AuthStorage.clear();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ProviderAuthScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.turquoise))
            : _profile == null
                ? _ErrorState(message: _error ?? 'Could not load your profile.', onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      if (_error != null) ...[
                        Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                        const SizedBox(height: 12),
                      ],
                      _field('Business name', _businessNameController),
                      _field('Description', _descriptionController, maxLines: 3),
                      _field('Phone', _phoneController, keyboardType: TextInputType.phone),

                      const _SectionLabel('Provider type'),
                      Row(
                        children: [
                          for (final type in ProviderType.all) ...[
                            Expanded(
                              child: _SelectableChip(
                                label: ProviderType.label(type),
                                selected: _providerType == type,
                                onTap: () => setState(() => _providerType = type),
                              ),
                            ),
                            if (type != ProviderType.all.last) const SizedBox(width: 8),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      const _SectionLabel('Categories offered'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final category in serviceCategories)
                            _SelectableChip(
                              label: category.label,
                              selected: _selectedCategories.contains(category.slug),
                              onTap: () => setState(() {
                                if (!_selectedCategories.remove(category.slug)) {
                                  _selectedCategories.add(category.slug);
                                }
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      const _SectionLabel('City'),
                      _dropdown(),
                      const SizedBox(height: 16),

                      _field('Team size', _teamSizeController, keyboardType: TextInputType.number),
                      _field('Years of experience', _yearsExperienceController, keyboardType: TextInputType.number),
                      _field('Service radius (km)', _serviceRadiusController, keyboardType: TextInputType.number),
                      _field('Languages (comma-separated)', _languagesController),
                      _field('Equipment (comma-separated)', _equipmentController),
                      _field('Certifications (comma-separated)', _certificationsController),

                      _switchCard('Insured', _isInsured, (v) => setState(() => _isInsured = v)),
                      const SizedBox(height: 12),
                      _switchCard('Available now', _isAvailableNow, (v) => setState(() => _isAvailableNow = v)),
                      const SizedBox(height: 20),

                      const _SectionLabel('Photos'),
                      Text(
                        "Paste links to photos hosted elsewhere — there's no file upload yet.",
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                      const SizedBox(height: 10),
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
                                controller: _photoUrlController,
                                decoration: const InputDecoration(
                                  hintText: 'https://…',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Material(
                            color: AppColors.turquoise,
                            borderRadius: BorderRadius.circular(kRadius),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(kRadius),
                              onTap: () {
                                final url = _photoUrlController.text.trim();
                                if (url.isEmpty) return;
                                setState(() {
                                  _photoUrls.add(url);
                                  _photoUrlController.clear();
                                });
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Icon(Icons.add, color: AppColors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final url in _photoUrls)
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
                              Expanded(child: Text(url, overflow: TextOverflow.ellipsis)),
                              InkWell(
                                onTap: () => setState(() => _photoUrls.remove(url)),
                                child: Icon(Icons.close, size: 18, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.turquoise,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  height: 18, width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                                )
                              : const Text('Save profile', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),

                      const SizedBox(height: 28),
                      const Divider(),
                      const SizedBox(height: 12),
                      const _SectionLabel('Claim your Google listing'),
                      Text(
                        _claimedPlaceId != null
                            ? 'This profile is linked to a real listing.'
                            : "If your business already shows up in customer search results, claim it so leads and reviews attach to this account. Unclaimed listings keep appearing in search — they just can't receive a lead.",
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(kRadius),
                          boxShadow: kCardShadow,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<KnownProvider>(
                            isExpanded: true,
                            hint: const Text('Choose your business'),
                            value: _selectedClaim,
                            items: [
                              for (final provider in _knownProviders)
                                DropdownMenuItem(value: provider, child: Text(provider.name)),
                            ],
                            onChanged: (value) => setState(() => _selectedClaim = value),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: (_saving || _selectedClaim == null) ? null : _claimListing,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.navy,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                          ),
                          child: const Text('Claim listing', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {TextInputType? keyboardType, int maxLines = 1}) {
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
              maxLines: maxLines,
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

  Widget _dropdown() {
    return Container(
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
    );
  }

  Widget _switchCard(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w500)),
        value: value,
        activeThumbColor: AppColors.turquoise,
        onChanged: onChanged,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy)),
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
          alignment: Alignment.center,
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: TextStyle(color: AppColors.muted), textAlign: TextAlign.center),
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
