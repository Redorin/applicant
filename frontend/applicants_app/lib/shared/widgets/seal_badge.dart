import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Vector-drawn office badge used on the login and splash screens in place
/// of a real seal/logo image (none exists yet) — a navy medallion with a
/// gold ring and monogram, rather than a plain flat color box.
class SealBadge extends StatelessWidget {
  const SealBadge({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.navyDeep,
        border: Border.all(color: AppColors.gold, width: size * .07),
      ),
      child: Center(
        child: Container(
          width: size * .76,
          height: size * .76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.gold.withValues(alpha: .55),
              width: size * .025,
            ),
          ),
          child: Text(
            'HP',
            style: TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w800,
              fontSize: size * .32,
              letterSpacing: -.5,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
