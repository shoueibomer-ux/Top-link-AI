import 'package:flutter/material.dart';

import '../api/api_client.dart';

class ServiceCategory {
  const ServiceCategory({
    required this.label,
    required this.icon,
    required this.whatWeCover,
    required this.workerNoun,
    required this.slug,
  });

  final String label;
  final IconData icon;

  // What kinds of jobs/issues this category handles — shown on the category
  // detail page above the "how it works" explanation.
  final String whatWeCover;

  // How providers in this category are referred to in the "how it works"
  // paragraph (e.g. "plumbers", "electricians") — keeps that paragraph's
  // wording trade-specific without hand-writing 9 near-identical blocks.
  final String workerNoun;

  // Matches matching_engine.CATEGORY_TAXONOMY on the backend — used to fetch
  // providers for this category without going through AI classification.
  final String slug;

  String get howItWorks =>
      "Once you select $label, you'll choose how urgent your request is, "
      "share your location, and we'll instantly match you with verified "
      "$workerNoun near you. You can review their ratings and match score "
      "before reaching out.";
}

/// Looks up a category by its backend slug (e.g. from a notification's
/// `category` field) — null if the slug doesn't match any known category.
/// Searches whatever `serviceCategories` currently holds — the static
/// fallback list until `loadCatalogFromApi` has resolved, the full
/// admin-managed catalog afterward.
ServiceCategory? findCategoryBySlug(String slug) {
  for (final category in serviceCategories) {
    if (category.slug == slug) return category;
  }
  return null;
}

/// A top-level grouping of services (e.g. "Home Services") shown on the
/// categories page — see catalog.Category on the backend. Mirrors
/// ServiceCategory's shape so a group's `icon`/`label` render the same way.
class ServiceCategoryGroup {
  const ServiceCategoryGroup({
    required this.label,
    required this.icon,
    required this.slug,
    required this.services,
  });

  final String label;
  final IconData icon;
  final String slug;
  final List<ServiceCategory> services;
}

/// Maps a backend `icon_name` (see catalog.Category/Service.icon_name) to a
/// concrete IconData. Falls back to a generic icon for any name added later
/// that this list doesn't yet know about, so a new admin-added
/// category/service never crashes the app — it just renders a plain icon
/// until this map is updated.
IconData iconForName(String name) {
  switch (name) {
    case 'construction':
      return Icons.construction;
    case 'home':
      return Icons.home;
    case 'directions_car':
      return Icons.directions_car;
    case 'business_center':
      return Icons.business_center;
    case 'celebration':
      return Icons.celebration;
    case 'person':
      return Icons.person;
    case 'plumbing':
      return Icons.plumbing;
    case 'electrical_services':
      return Icons.electrical_services;
    case 'ac_unit':
      return Icons.ac_unit;
    case 'carpenter':
      return Icons.carpenter;
    case 'format_paint':
      return Icons.format_paint;
    case 'handyman':
      return Icons.handyman;
    case 'home_repair_service':
      return Icons.home_repair_service;
    case 'precision_manufacturing':
      return Icons.precision_manufacturing;
    case 'window':
      return Icons.window;
    case 'cleaning_services':
      return Icons.cleaning_services;
    case 'local_shipping':
      return Icons.local_shipping;
    case 'chair':
      return Icons.chair;
    case 'build':
      return Icons.build;
    case 'car_repair':
      return Icons.car_repair;
    case 'local_car_wash':
      return Icons.local_car_wash;
    case 'build_circle':
      return Icons.build_circle;
    case 'calculate':
      return Icons.calculate;
    case 'campaign':
      return Icons.campaign;
    case 'language':
      return Icons.language;
    case 'computer':
      return Icons.computer;
    case 'camera_alt':
      return Icons.camera_alt;
    case 'event':
      return Icons.event;
    case 'speaker':
      return Icons.speaker;
    case 'content_cut':
      return Icons.content_cut;
    case 'spa':
      return Icons.spa;
    case 'fitness_center':
      return Icons.fitness_center;
    case 'school':
      return Icons.school;
    case 'layers':
      return Icons.layers;
    case 'roofing':
      return Icons.roofing;
    case 'foundation':
      return Icons.foundation;
    case 'kitchen':
      return Icons.kitchen;
    case 'bathtub':
      return Icons.bathtub;
    case 'delivery_dining':
      return Icons.delivery_dining;
    case 'warehouse':
      return Icons.warehouse;
    case 'gavel':
      return Icons.gavel;
    case 'restaurant':
      return Icons.restaurant;
    case 'security':
      return Icons.security;
    case 'park':
      return Icons.park;
    case 'grass':
      return Icons.grass;
    case 'snowing':
      return Icons.snowing;
    case 'forest':
      return Icons.forest;
    case 'yard':
      return Icons.yard;
    default:
      return Icons.build;
  }
}

/// Groups fetched from GET /api/catalog/categories/ — empty until
/// `loadCatalogFromApi` resolves at least once. The customer-facing
/// categories page (CategoryStep) reads this for the group-first
/// drill-down UI; everything else keeps reading the flat `serviceCategories`
/// list below, which `loadCatalogFromApi` also populates from the same call.
List<ServiceCategoryGroup> serviceCategoryGroups = [];

Future<void>? _catalogLoadFuture;

/// Fetches the admin-managed category/service tree and, on success, expands
/// `serviceCategories`/`serviceCategoryGroups` to match it. Safe to call
/// from multiple widgets — only the first call actually hits the network;
/// later callers await the same in-flight/completed future. Leaves the
/// static fallback list in place on any failure (offline, server down),
/// so nothing that already depends on `serviceCategories` regresses.
Future<void> loadCatalogFromApi([ApiClient? client]) {
  return _catalogLoadFuture ??= _loadCatalog(client ?? ApiClient());
}

Future<void> _loadCatalog(ApiClient client) async {
  try {
    final groups = await client.getCatalog();
    if (groups.isEmpty) {
      _catalogLoadFuture = null;
      return;
    }
    serviceCategoryGroups = groups;
    serviceCategories = [for (final group in groups) ...group.services];
  } catch (_) {
    // Keep the static fallback, and clear the cached future so the next
    // caller retries instead of being stuck with a failure forever.
    _catalogLoadFuture = null;
  }
}

/// The pre-Phase-1B static list of 9 trade categories — used to seed
/// `serviceCategories` immediately (so the app has something to render
/// before the first network round trip) and as the permanent fallback if
/// `loadCatalogFromApi` never succeeds.
const _fallbackServiceCategories = [
  ServiceCategory(
    label: 'Plumbing',
    icon: Icons.plumbing,
    whatWeCover:
        'We cover leaky pipes, clogged drains, water heater installation and '
        'repair, fixture replacements, toilet and faucet repairs, and general '
        'plumbing emergencies.',
    workerNoun: 'plumbers',
    slug: 'plumbing',
  ),
  ServiceCategory(
    label: 'Electrical',
    icon: Icons.electrical_services,
    whatWeCover:
        'We cover wiring and rewiring, outlet and switch installation, '
        'breaker panel upgrades, lighting installation, and electrical '
        'safety inspections and repairs.',
    workerNoun: 'electricians',
    slug: 'electrical',
  ),
  ServiceCategory(
    label: 'Carpentry',
    icon: Icons.carpenter,
    whatWeCover:
        'We cover custom cabinetry, framing, furniture building and repair, '
        'deck construction, trim work, and other wood-based construction '
        'projects.',
    workerNoun: 'carpenters',
    slug: 'carpentry',
  ),
  ServiceCategory(
    label: 'HVAC',
    icon: Icons.ac_unit,
    whatWeCover:
        'We cover furnace and air conditioner repair and installation, '
        'heating and cooling system maintenance, ventilation and ductwork, '
        'and thermostat setup.',
    workerNoun: 'HVAC technicians',
    slug: 'hvac',
  ),
  ServiceCategory(
    label: 'Painting',
    icon: Icons.format_paint,
    whatWeCover:
        'We cover interior and exterior painting, wall and trim finishing, '
        'touch-ups, surface preparation, and color consultation for homes '
        'and businesses.',
    workerNoun: 'painters',
    slug: 'painting',
  ),
  ServiceCategory(
    label: 'Construction/Finishing',
    icon: Icons.construction,
    whatWeCover:
        'We cover full renovations, remodels, general contracting, new-build '
        'construction, and finishing work like flooring, trim, and fixtures.',
    workerNoun: 'contractors',
    slug: 'construction-finishing',
  ),
  ServiceCategory(
    label: 'Drywall & Decor',
    icon: Icons.home_repair_service,
    whatWeCover:
        'We cover drywall installation and repair, ceiling work, molding and '
        'trim, texture and finishing, and general interior decor '
        'installation.',
    workerNoun: 'drywall and decor specialists',
    slug: 'drywall-decor',
  ),
  ServiceCategory(
    label: 'Metalwork/Aluminum',
    icon: Icons.precision_manufacturing,
    whatWeCover:
        'We cover welding, custom railings and gates, aluminum and steel '
        'fabrication, structural metalwork, and repair of metal fixtures.',
    workerNoun: 'metalworkers',
    slug: 'metalwork-aluminum',
  ),
  ServiceCategory(
    label: 'Glass & Mirrors',
    icon: Icons.window,
    whatWeCover:
        'We cover window replacement and repair, custom mirror installation, '
        'glass shower doors and enclosures, and storefront or display glass '
        'work.',
    workerNoun: 'glass and mirror specialists',
    slug: 'glass-mirrors',
  ),
];

/// The flat list every existing screen reads (category grids, the provider
/// profile's service picker, notification/history lookups). Starts as the
/// static fallback and is replaced wholesale once `loadCatalogFromApi`
/// resolves. Mutable (not const) so that replacement can happen in place.
List<ServiceCategory> serviceCategories = List.of(_fallbackServiceCategories);
