import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';

/// Subtle 1.03x scale-up on hover — first use of [AnimatedScale] in the app.
/// Wrap a primary CTA (not every borderless toolbar button) to avoid a busy
/// feel from many buttons scaling at once.
class HoverScale extends StatefulWidget {
  const HoverScale({super.key, required this.child, this.glow = false});

  final Widget child;

  /// Also fades in an accent-color glow (a soft [BoxShadow]) alongside the
  /// scale — used for Export-related buttons per the spec's glow-on-hover ask.
  final bool glow;

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scaled = AnimatedScale(
      scale: _hover ? 1.03 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: widget.child,
    );

    final content = !widget.glow
        ? scaled
        : AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: AppRadius.smAll,
              boxShadow: _hover
                  ? [
                      BoxShadow(
                        color: AppColors.actionBlue.withValues(alpha: .35),
                        blurRadius: 12,
                      ),
                    ]
                  : const [],
            ),
            child: scaled,
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: content,
    );
  }
}
