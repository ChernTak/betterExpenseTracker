import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// A small caps label sitting above a field, matching the design system's
/// "EMAIL ADDRESS" / "TRANSACTION AMOUNT" look — used instead of Flutter's
/// default floating InputDecoration label wherever that exact style matters.
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
