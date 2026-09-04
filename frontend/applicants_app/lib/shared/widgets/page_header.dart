import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Consistent screen-level title, applied to every top-level page so the
/// user always has a visual confirmation of "where am I" beyond the
/// sidebar's active-item highlight.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.showBreadcrumb = true,
    this.parentTitle,
    this.onParentTap,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool showBreadcrumb;

  /// When set, breadcrumb becomes: Dashboard › [parentTitle] › [title].
  final String? parentTitle;

  /// Navigation callback when the parent breadcrumb link is tapped.
  final VoidCallback? onParentTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBreadcrumb) ...[
          _Breadcrumb(
            currentTitle: title,
            parentTitle: parentTitle,
            onParentTap: onParentTap,
          ),
          const SizedBox(height: 6),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.pageTitle),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: AppTypography.pageSubtitle),
                  ],
                ],
              ),
            ),
            ...?actions,
          ],
        ),
      ],
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.currentTitle,
    this.parentTitle,
    this.onParentTap,
  });

  final String currentTitle;
  final String? parentTitle;
  final VoidCallback? onParentTap;

  @override
  Widget build(BuildContext context) {
    if (currentTitle == 'Dashboard') {
      return const Text('Dashboard', style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BreadcrumbLink('Dashboard', onTap: () => context.go('/dashboard')),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('›', style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          )),
        ),
        if (parentTitle != null) ...[
          _BreadcrumbLink(parentTitle!, onTap: onParentTap ?? () {}),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('›', style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            )),
          ),
        ],
        Text(currentTitle, style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        )),
      ],
    );
  }
}

class _BreadcrumbLink extends StatefulWidget {
  const _BreadcrumbLink(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_BreadcrumbLink> createState() => _BreadcrumbLinkState();
}

class _BreadcrumbLinkState extends State<_BreadcrumbLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.actionBlue,
            decoration: _hover ? TextDecoration.underline : TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
