import 'package:flutter/material.dart';

class ServiceCategory {
  const ServiceCategory(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;
}

const serviceCategories = [
  ServiceCategory(
    'Plumbing',
    Icons.plumbing,
    'Leaky pipes, drain clogs, water heater installs, fixture repairs.',
  ),
  ServiceCategory(
    'Electrical',
    Icons.electrical_services,
    'Wiring, outlets, breaker panels, lighting installation.',
  ),
  ServiceCategory(
    'Carpentry',
    Icons.carpenter,
    'Custom cabinets, framing, furniture, deck building.',
  ),
  ServiceCategory(
    'HVAC',
    Icons.ac_unit,
    'Heating, cooling, furnace and AC repair, ventilation and duct work.',
  ),
  ServiceCategory(
    'Painting',
    Icons.format_paint,
    'Interior and exterior painting, wall finishing, touch-ups.',
  ),
  ServiceCategory(
    'Construction/Finishing',
    Icons.construction,
    'Renovations, remodels, general contracting, new builds.',
  ),
  ServiceCategory(
    'Drywall & Decor',
    Icons.home_repair_service,
    'Drywall installation and repair, ceilings, molding, interior decor.',
  ),
  ServiceCategory(
    'Metalwork/Aluminum',
    Icons.precision_manufacturing,
    'Welding, railings, gates, aluminum and steel fabrication.',
  ),
  ServiceCategory(
    'Glass & Mirrors',
    Icons.window,
    'Window replacement, mirror installs, glass repair, shower doors.',
  ),
];
