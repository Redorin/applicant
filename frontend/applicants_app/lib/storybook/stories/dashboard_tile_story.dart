// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_typography.dart';

final dashboardTileStories = [
  Story(
    name: 'Dashboard Tile / KPI Card',
    builder: (context) => const Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _KPITile(
          icon: Icons.people_outline,
          iconColor: AppColors.actionBlue,
          iconBg: Color(0xFFE0E7FF),
          label: 'Total Applicants',
          value: '25,000',
        ),
        _KPITile(
          icon: Icons.pending_actions_outlined,
          iconColor: Color(0xFF92400E),
          iconBg: Color(0xFFFEF3C7),
          label: 'On Process',
          value: '4,714',
        ),
        _KPITile(
          icon: Icons.check_circle_outline,
          iconColor: Color(0xFF166534),
          iconBg: Color(0xFFDCFCE7),
          label: 'Hired This Year',
          value: '128',
        ),
        _KPITile(
          icon: Icons.mail_outline,
          iconColor: AppColors.actionBlue,
          iconBg: Color(0xFFE0E7FF),
          label: 'Applications',
          value: '3,450',
        ),
      ],
    ),
  ),
];

class _KPITile extends StatelessWidget {
  const _KPITile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: AppTypography.helper
                      .copyWith(color: AppColors.muted)),
              const SizedBox(height: 2),
              Text(value,
                  style: AppTypography.kpiNumber),
            ],
          ),
        ],
      ),
    );
  }
}
