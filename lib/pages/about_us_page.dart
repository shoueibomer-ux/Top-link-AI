import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/app_drawer.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('About Us')),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.turquoise,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.info_outline, color: AppColors.white, size: 28),
            ),
            const SizedBox(height: 24),
            const Text(
              'About Us',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(kRadius),
                boxShadow: kCardShadow,
              ),
              child: const Text(
                'Top-Link AI connects clients with trusted local service '
                'providers using AI-powered matching. We started in Edmonton, '
                'Alberta, with a simple goal: make it fast and easy to find '
                'the right professional for any job — starting with skilled '
                'trades like plumbing, electrical, carpentry, and more.',
                style: TextStyle(fontSize: 15, height: 1.6, color: AppColors.navy),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
