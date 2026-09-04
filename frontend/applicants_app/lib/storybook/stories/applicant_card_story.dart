// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_typography.dart';

final applicantCardStories = [
  Story(
    name: 'Applicant Card / Default',
    builder: (context) => const _ApplicantCard(
      name: 'Dela Cruz, Juan',
      course: 'Bachelor of Science in Computer Science',
      municipality: 'Lingayen',
    ),
  ),
  Story(
    name: 'Applicant Card / Long Name',
    builder: (context) => const _ApplicantCard(
      name: 'Gonzales-Alvarez, Maria Theresa',
      course: 'Associate in Health Science Education',
      municipality: 'Dagupan City',
    ),
  ),
  Story(
    name: 'Applicant Card / No Course',
    builder: (context) => const _ApplicantCard(
      name: 'Santos, Pedro',
      municipality: 'Urdaneta',
    ),
  ),
];

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({
    required this.name,
    this.course,
    required this.municipality,
  });

  final String name;
  final String? course;
  final String municipality;

  static const _avatarColors = [
    Color(0xFF5B6ABF),
    Color(0xFFE74C5E),
    Color(0xFFF5A623),
    Color(0xFF2D325A),
    Color(0xFF16A085),
    Color(0xFF8E44AD),
    Color(0xFFE67E22),
  ];

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final color = _avatarColors[name.isEmpty
        ? 0
        : name.codeUnitAt(0) % _avatarColors.length];

    return Container(
      width: 350,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color,
            child: Text(initial,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body
                        .copyWith(fontWeight: FontWeight.w600)),
                if (course != null && course!.isNotEmpty)
                  Text(course!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted)),
                Text(municipality,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
