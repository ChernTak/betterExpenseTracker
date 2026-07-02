import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

/// The "Insights" tab. AI-generated spending insights (Module 2) aren't
/// built yet — this stays honest about that instead of faking data, the
/// same way Scan/Voice input show as visible-but-disabled today.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppColors.primaryMuted, shape: BoxShape.circle),
              child: const Icon(Icons.insights, color: AppColors.primary, size: 32),
            ),
            const SizedBox(height: 20),
            const Text(
              'Insights are coming soon',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Personalised spending insights are still being built. '
              'In the meantime, check the Guide tab for this month\'s summary.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
