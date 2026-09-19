import 'package:flutter/material.dart';

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
ServiceCategory? findCategoryBySlug(String slug) {
  for (final category in serviceCategories) {
    if (category.slug == slug) return category;
  }
  return null;
}

const serviceCategories = [
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
