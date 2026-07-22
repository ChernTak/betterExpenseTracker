import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

/// Placeholder for the food-recommendation tab — wired into MainShell's
/// bottom nav now so the 5-tab layout is in place, but the feature itself
/// (merchant suggestions near the user's location/budget) isn't built yet.
class FoodRecommendationScreen extends StatelessWidget {
  const FoodRecommendationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_outlined, size: 56, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'Food Recommendations',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            SizedBox(height: 8),
            Text(
              'Coming soon — budget-aware merchant suggestions near you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
