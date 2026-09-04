import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// The one card surface for the app: uppercase muted title, hairline
/// underline, then content. Replaces the three hand-copied variants that
/// had accumulated (form_bits' SectionCard, dashboard's private _Card,
/// preferences' private _Section) so a future style tweak only happens once.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.showDivider = true,
    this.padding,
    this.trailing,
    this.interactive = false,
    this.fillHeight = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool showDivider;
  final EdgeInsetsGeometry? padding;
  final Widget? trailing;

  /// Opt-in 2px hover-lift + bigger shadow, for cards that are actually
  /// clickable (e.g. the dashboard's chart cards). Off by default so static,
  /// non-clickable cards (Master Data's form sections, etc.) don't gain a
  /// false "this is clickable" affordance.
  final bool interactive;

  /// When true the card expands to fill the full height provided by its
  /// parent (e.g. CrossAxisAlignment.stretch). Off by default so the card
  /// sizes to its content.
  final bool fillHeight;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final lifted = widget.interactive && _hover;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
      width: double.infinity,
      padding: widget.padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: lifted ? .12 : .06),
            blurRadius: lifted ? 16 : 8,
            offset: Offset(0, lifted ? 6 : 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: widget.fillHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.trailing == null
              ? _TitleBlock(title: widget.title, subtitle: widget.subtitle)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _TitleBlock(
                          title: widget.title, subtitle: widget.subtitle),
                    ),
                    const SizedBox(width: 12),
                    widget.trailing!,
                  ],
                ),
          widget.showDivider
              ? const Divider(height: 18)
              : const SizedBox(height: AppSpacing.md),
          if (widget.fillHeight)
            Expanded(child: widget.child)
          else
            widget.child,
        ],
      ),
    );

    if (!widget.interactive) return card;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: card,
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: AppTypography.sectionTitle),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: AppTypography.helper),
        ],
      ],
    );
  }
}
