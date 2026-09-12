import 'package:flutter/material.dart';

class ServiceCategory {
  const ServiceCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

const serviceCategories = [
  ServiceCategory('Plumbing', Icons.plumbing),
  ServiceCategory('Electrical', Icons.electrical_services),
  ServiceCategory('Carpentry', Icons.carpenter),
  ServiceCategory('HVAC', Icons.ac_unit),
  ServiceCategory('Painting', Icons.format_paint),
  ServiceCategory('Construction/Finishing', Icons.construction),
  ServiceCategory('Drywall & Decor', Icons.home_repair_service),
  ServiceCategory('Metalwork/Aluminum', Icons.precision_manufacturing),
  ServiceCategory('Glass & Mirrors', Icons.window),
];
