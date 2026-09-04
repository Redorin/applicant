import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Stand-in for screens not yet built (replaced milestone by milestone).
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction_outlined,
              size: 40, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(title, style: AppTypography.pageTitle.copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          const Text('Coming in a later milestone.', style: AppTypography.helper),
        ],
      ),
    );
  }
}
