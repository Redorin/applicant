import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../shared/widgets/keyboard_focus_ring.dart';
import 'sidebar_nav_items.dart';
import 'sidebar_state.dart';

/// Always-visible 74px icon rail. Never resizes — nav labels only ever
/// appear in [SidebarDrawer], which opens as an overlay on top of this rail
/// (and is wide enough to fully cover it) rather than pushing it aside.
class SidebarRail extends ConsumerWidget {
  const SidebarRail({super.key, required this.currentPath});

  static const width = 74.0;

  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthTotal = ref.watch(healthBadgeTotalProvider);

    return Container(
      width: width,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.navy, AppColors.navyDeep],
        ),
      ),
      child: Semantics(
        container: true,
        label: 'Primary navigation',
        child: Column(
          children: [
            const SizedBox(height: 16),
            _Logo(onTap: () => ref.read(sidebarDrawerProvider.notifier).open()),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 24,
                height: 1,
                child: ColoredBox(color: Color(0x14FFFFFF)),
              ),
            ),
            for (var i = 0; i < sidebarNavItems.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _RailIconButton(
                  icon: sidebarNavItems[i].icon,
                  tooltip: sidebarNavItems[i].label,
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
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 24,
                    height: 1,
                    child: ColoredBox(color: Color(0x14FFFFFF)),
                  ),
                ),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RailIconButton(
                icon: Icons.settings,
                tooltip: 'Preferences',
                active: currentPath.startsWith('/preferences'),
                // Preferences intentionally bypasses the unsaved-changes
                // guard — matches the sidebar's existing behavior.
                onTap: () => context.go('/preferences'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.onTap});
  final VoidCallback onTap;

  static const _seal = Image(
    image: AssetImage('assets/images/pgo_seal.png'),
    width: 40,
    height: 40,
  );

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Applicants Information System',
      child: ClipRRect(
        borderRadius: AppRadius.mdAll,
        child: InkWell(onTap: onTap, child: _seal),
      ),
    );
  }
}

/// Rounded icon-only rail button (nav items, hamburger, gear). Active state
/// is drawn as a separate inset bar (top:8/bottom:8, rounded outer corner)
/// rather than a border on the button itself, since a `Border` always runs
/// the full length of its edge and can't produce an inset bar.
class _RailIconButton extends StatefulWidget {
  const _RailIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final int badgeCount;

  @override
  State<_RailIconButton> createState() => _RailIconButtonState();
}

class _RailIconButtonState extends State<_RailIconButton>
    with SingleTickerProviderStateMixin {
  bool _hover = false;

  late final _wiggleController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 350));

  // Small rotation oscillation (0 -> +0.1rad -> -0.1rad -> 0) played once on
  // hover-enter, layered on top of the existing color/opacity
  // AnimatedContainer rather than replacing it.
  late final _wiggle = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.10), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.10, end: -0.10), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -0.10, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _wiggleController, curve: Curves.easeInOut));

  @override
  void dispose() {
    _wiggleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;

    return Tooltip(
      message: widget.tooltip,
      textStyle: const TextStyle(color: Colors.white, fontSize: 11),
      decoration: BoxDecoration(
        color: AppColors.navyDeep,
        borderRadius: BorderRadius.circular(6),
      ),
      child: KeyboardFocusRing(
        borderRadius: AppRadius.mdAll,
        onActivate: widget.onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: MouseRegion(
                  onEnter: (_) {
                    setState(() => _hover = true);
                    _wiggleController.forward(from: 0);
                  },
                  onExit: (_) => setState(() => _hover = false),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white.withValues(alpha: .04)
                            : _hover
                            ? Colors.white.withValues(alpha: .06)
                            : Colors.transparent,
                        borderRadius: AppRadius.mdAll,
                      ),
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _wiggle,
                          builder: (context, child) =>
                              Transform.rotate(angle: _wiggle.value, child: child),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                widget.icon,
                                size: 19,
                                color: active
                                    ? AppColors.gold
                                    : _hover
                                    ? AppColors.sidebarText
                                    : AppColors.sidebarTextDim,
                              ),
                              if (widget.badgeCount > 0)
                                Positioned(
                                  right: -5,
                                  top: -5,
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: AppColors.danger,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.navy,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
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
