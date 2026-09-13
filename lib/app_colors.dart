import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const navy = Color(0xFF0B1F3A);
  static const turquoise = Color(0xFF19C3B1);
  static const white = Color(0xFFFFFFFF);
  static const lightBackground = Color(0xFFF4F7FA);

  /// Secondary/caption text — a muted, slightly gray tint of navy.
  static Color get muted => navy.withValues(alpha: 0.6);
}
