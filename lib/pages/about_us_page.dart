import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/app_drawer.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  static const tagline = 'Connecting Edmonton homeowners with trusted local service providers, faster.';

  static const customerPoints = [
    'Describe what you need — our AI matches you to the right local provider',
    'Compare real, verified professionals: electricians, plumbers, cleaners, and more',
    'See ratings and availability before you reach out',
    'No more endless searching or cold calls',
  ];

  static const providerPoints = [
    'Get discovered by customers actively looking for your service',
    'Free to join, no commitment required',
    'Receive leads matched to your trade and service area',
    'Build your reputation with real customer reviews',
  ];

  static const steps = [
    'Tell us what you need',
    'Get matched instantly',
    'Connect and get it done',
  ];

  static const categories = [
    'Electrical',
    'Plumbing',
    'HVAC',
    'Cleaning',
    'Contractors',
    'Automotive',
    'Landscaping',
    'Moving',
    'Events',
  ];

  static const footerNote = 'Launching in Edmonton — expanding to Calgary, Fort McMurray, and Red Deer soon.';

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
            const SizedBox(height: 12),
            const Text(
              tagline,
              style: TextStyle(fontSize: 17, height: 1.5, fontWeight: FontWeight.w500, color: AppColors.navy),
            ),
            const SizedBox(height: 24),
            const _SectionCard(
              title: 'For Customers',
              child: _BulletList(points: customerPoints),
            ),
            const SizedBox(height: 16),
            const _SectionCard(
              title: 'For Providers',
              child: _BulletList(points: providerPoints),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'How It Works',
              child: Column(
                children: [
                  for (var i = 0; i < steps.length; i++) _StepRow(number: i + 1, text: steps[i]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Popular categories',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final category in categories) _CategoryChip(label: category),
                  Text('and more', style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 18, color: AppColors.turquoise),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(footerNote, style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted)),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.points});

  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final point in points)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_circle, size: 18, color: AppColors.turquoise),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(point, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.navy)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.turquoise, shape: BoxShape.circle),
            child: Text(
              '$number',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.turquoise.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy),
      ),
    );
  }
}
