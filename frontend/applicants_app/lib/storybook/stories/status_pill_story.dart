// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_typography.dart';

final statusPillStories = [
  Story(
    name: 'Status Pill / All Variants',
    builder: (context) => const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatusPill('Active File'),
        _StatusPill('On Process'),
        _StatusPill('For Interview'),
        _StatusPill('Hired'),
        _StatusPill('Rejected'),
        _StatusPill('Pending'),
        _StatusPill('Unknown Status'),
      ],
    ),
  ),
  Story(
    name: 'Status Pill / Single',
    builder: (context) => const _StatusPill('On Process'),
  ),
];

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (status.toLowerCase()) {
      case 'hired':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
      case 'rejected':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
      case 'on process':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
      case 'for interview':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E40AF);
      case 'active file':
        bg = const Color(0xFFE0E7FF);
        fg = const Color(0xFF4338CA);
      default:
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF374151);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: AppRadius.pillAll),
      child: Text(status,
          style: AppTypography.chip.copyWith(color: fg)),
    );
  }
}
