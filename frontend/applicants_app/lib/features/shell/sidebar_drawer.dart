import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/keyboard_focus_ring.dart';
import 'sidebar_nav_items.dart';
import 'sidebar_state.dart';

/// 240px overlay drawer content — brand header, full nav labels, pinned
/// Preferences + footer. Pure content: the slide animation and backdrop
/// that carry this panel on/off screen live in app_shell.dart, not here.
class SidebarDrawer extends ConsumerWidget {
  const SidebarDrawer({super.key, required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthTotal = ref.watch(healthBadgeTotalProvider);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.navy, AppColors.navyDeep],
        ),
      ),
      child: Semantics(
        container: true,
        label: 'Navigation menu',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BrandRow(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: SizedBox(
                height: 1,
                child: ColoredBox(color: Color(0x14FFFFFF)),
              ),
            ),
            for (var i = 0; i < sidebarNavItems.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _DrawerRow(
                  icon: sidebarNavItems[i].icon,
                  label: sidebarNavItems[i].label,
                  active: currentPath.startsWith(sidebarNavItems[i].path),
                  badgeCount: sidebarNavItems[i].path == '/data-health'
                      ? healthTotal
                      : 0,
                  onTap: () => handleNavTap(
                    context,
                    ref,
                    currentPath: currentPath,
                    targetPath: sidebarNavItems[i].path,
                  ),
                ),
              ),
              if (i == dividerAfterIndex)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: SizedBox(
                    height: 1,
                    child: ColoredBox(color: Color(0x14FFFFFF)),
                  ),
                ),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _DrawerRow(
                icon: Icons.settings,
                label: 'Preferences',
                active: currentPath.startsWith('/preferences'),
                // Preferences intentionally bypasses the unsaved-changes
                // guard — matches the sidebar's existing behavior.
                onTap: () => context.go('/preferences'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Text(
                'Human Resources Management Development Office\nProvincial Government of Pangasinan',
                style: TextStyle(
                  color: AppColors.sidebarTextDim,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow();

  static const _seal = Image(
    image: AssetImage('assets/images/pgo_seal.png'),
    width: 40,
    height: 40,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(borderRadius: AppRadius.mdAll, child: _seal),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Applicants Info System',
                  maxLines: 2,
                  style: AppTypography.navLabel.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Version 3.0.0',
                  style: TextStyle(
                    color: AppColors.sidebarTextDim,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + label nav row (used for both the 7 main items and Preferences).
/// Active state is a separate inset gold bar (top:8/bottom:8), matching the
/// rail's treatment, not a full-height Border.
class _DrawerRow extends StatefulWidget {
  const _DrawerRow({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final bool active;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  State<_DrawerRow> createState() => _DrawerRowState();
}

class _DrawerRowState extends State<_DrawerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final textColor = active
        ? Colors.white
        : (_hover ? AppColors.sidebarText : AppColors.sidebarTextDim);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: KeyboardFocusRing(
        onActivate: widget.onTap,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Stack(
            children: [
              Container(
                color: active
                    ? Colors.white.withValues(alpha: .04)
                    : _hover
                    ? Colors.white.withValues(alpha: .06)
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 25,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 17, color: textColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.navLabel.copyWith(
                          color: textColor,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.badgeCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                        child: Text(
                          '${widget.badgeCount}',
                          style: AppTypography.chip.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (active)
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 3,
                    decoration: const BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
