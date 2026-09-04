import 'package:flutter/material.dart';

/// Colored circle showing a name's first initial — cycled by that initial's
/// character code. Purely decorative, no semantic meaning, so kept as its
/// own small palette rather than added to AppColors (unlike the
/// status/danger colors, which are reused globally). Shared by the browse
/// grid's applicant cell and the duplicate-detection banner.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.name, this.radius = 14});

  final String name;
  final double radius;

  static const _colors = [
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
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final color = _colors[trimmed.isEmpty ? 0 : trimmed.codeUnitAt(0) % _colors.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 12 / 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
