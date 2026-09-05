import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Small-caps label above a field, replacing Flutter's default floating InputDecoration label where that exact look matters.
class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  final Widget? trailing;

  const LabeledField({super.key, required this.label, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: AppColors.textSecondary,
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
