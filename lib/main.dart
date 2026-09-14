import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'subscription/app_entry_point.dart';

void main() {
  runApp(const TopLinkApp());
}

class TopLinkApp extends StatelessWidget {
  const TopLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Top Link AI',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.lightBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.turquoise,
          primary: AppColors.turquoise,
          secondary: AppColors.navy,
          surface: AppColors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.navy,
          foregroundColor: AppColors.white,
        ),
      ),
      home: const AppEntryPoint(),
    );
  }
}
