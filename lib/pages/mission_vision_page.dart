import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/app_drawer.dart';

class MissionVisionPage extends StatelessWidget {
  const MissionVisionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Mission & Vision')),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const [
            _StatementCard(
              icon: Icons.flag_outlined,
              title: 'Our Mission',
              body: 'To eliminate the guesswork in finding reliable service '
                  'providers by using AI to match clients with the right '
                  'professional, every time.',
            ),
            SizedBox(height: 16),
            _StatementCard(
              icon: Icons.rocket_launch_outlined,
              title: 'Our Vision',
              body: 'To become the go-to platform connecting people across '
                  'every industry and profession, powered by intelligent, '
                  'instant matching.',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.turquoise.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.turquoise),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: TextStyle(fontSize: 14, height: 1.6, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
