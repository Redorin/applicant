import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/skip_to_content_link.dart';
import 'sidebar_drawer.dart';
import 'sidebar_rail.dart';
import 'sidebar_state.dart';
import 'toast_provider.dart';

/// Width of the overlay drawer panel — shared by [_DrawerOverlay] (the
/// sliding panel itself) and [_SidebarHoverZone] (the hover-detection band,
/// which must match the drawer's footprint since it's a superset of the
/// rail's 74px width).
const _drawerWidth = 240.0;

/// Below this window width, the 74px rail hides entirely (reclaiming space)
/// in favor of a slim invisible hover strip — see [_SidebarHoverZone].
const _narrowBreakpoint = 900.0;

/// Closed-state hover-trigger width once the rail itself is hidden below
/// [_narrowBreakpoint]. There's no manual toggle in this sidebar design (see
/// _SidebarHoverZone's doc comment) — this strip is the only way to reveal
/// the drawer at narrow widths, a discoverability tradeoff accepted in favor
/// of reclaiming the rail's 74px on small windows.
const _narrowHoverStripWidth = 10.0;

/// The persistent app frame: icon rail, overlay nav drawer, content outlet,
/// and toast overlay.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // Target for the skip-to-content link (see SkipToContentLink below) — the
  // first Tab stop in the app, letting keyboard users jump past the sidebar
  // straight to the page content.
  final _contentFocusNode = FocusNode(debugLabel: 'AppShell content');

  @override
  void dispose() {
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toast = ref.watch(toastProvider);
    final isNarrow = MediaQuery.sizeOf(context).width < _narrowBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.ground,
      body: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isNarrow) SidebarRail(currentPath: widget.currentPath),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Focus(focusNode: _contentFocusNode, child: widget.child),
                    ),
                    // Toast overlay, bottom-right, as in the old app.
                    if (toast != null)
                      Positioned(
                        right: 24,
                        bottom: 18,
                        child: _Toast(data: toast),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Always mounted (so a close can play its reverse animation
          // instead of vanishing instantly) but renders nothing once fully
          // closed — see _DrawerOverlayState.build. Positioned.fill (rather
          // than relying on Stack's non-positioned-child sizing) guarantees
          // this covers the full Scaffold body regardless of how the Row
          // above sizes itself.
          Positioned.fill(child: _DrawerOverlay(currentPath: widget.currentPath)),
          // Topmost and translucent: hit-tested first every frame (so the
          // drawer's own slide-in animation can never cover or steal its
          // hover events) but never blocks taps or the nested hover regions
          // in the rail buttons / drawer rows beneath it. See
          // _SidebarHoverZone doc comment for why this must stay last.
          const _SidebarHoverZone(),
          // First in Tab order (and last in paint order, so it renders on
          // top when focused) — skips the sidebar entirely for keyboard users.
          SkipToContentLink(onActivate: () => _contentFocusNode.requestFocus()),
        ],
      ),
    );
  }
}

/// Hover band that opens/closes the drawer. Width tracks whichever footprint
/// is currently real: [SidebarRail.width] (74px, or [_narrowHoverStripWidth]
/// below [_narrowBreakpoint] once the rail itself is hidden) while closed —
/// so hovering ordinary page content past that edge does nothing — widening
/// to [_drawerWidth] (240px) once open, so hovering the now-visible drawer
/// (which covers the rail underneath) keeps it open, and leaving that full
/// band closes it immediately (the existing 220ms slide-out in
/// [_DrawerOverlay] still plays, just triggered without delay).
///
/// This must be a single, always-mounted, non-animated region rather than
/// separate MouseRegions on the rail and on the drawer panel. Two separate
/// regions have a real correctness gap: as the drawer slides in over the
/// rail, a rail-side onExit can misfire mid-animation (flicker: closes
/// right after opening), and if the cursor leaves before the drawer's
/// hit-test region reaches it, the drawer's onEnter/onExit may never fire
/// at all, leaving the drawer stuck open. A single region sidesteps both,
/// since it's never covered by the drawer's content. Its width is driven by
/// the boolean provider directly (flips instantly), not by the slide
/// animation, so widening happens well before the 220ms visual slide
/// finishes — no timing race with the animation.
class _SidebarHoverZone extends ConsumerWidget {
  const _SidebarHoverZone();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = ref.watch(sidebarDrawerProvider);
    final isNarrow = MediaQuery.sizeOf(context).width < _narrowBreakpoint;
    final closedWidth = isNarrow ? _narrowHoverStripWidth : SidebarRail.width;
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: isOpen ? _drawerWidth : closedWidth,
      child: MouseRegion(
        opaque: false,
        onEnter: (_) => ref.read(sidebarDrawerProvider.notifier).open(),
        onExit: (_) => ref.read(sidebarDrawerProvider.notifier).close(),
      ),
    );
  }
}

/// Backdrop + sliding drawer panel, layered on top of the rail and page
/// content. Always mounted (so [sidebarDrawerProvider] flipping to false
/// can play a reverse slide-out instead of the panel just vanishing) but
/// renders nothing — via [AnimationController.isDismissed] — once the
/// close animation finishes, so it's inert (no hit-testable widgets) while
/// closed.
class _DrawerOverlay extends ConsumerStatefulWidget {
  const _DrawerOverlay({required this.currentPath});
  final String currentPath;

  @override
  ConsumerState<_DrawerOverlay> createState() => _DrawerOverlayState();
}

class _DrawerOverlayState extends ConsumerState<_DrawerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );
    _slide = Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() => ref.read(sidebarDrawerProvider.notifier).close();

  @override
  Widget build(BuildContext context) {
    // Drives the controller from provider flips — forward to open, reverse
    // (rather than an instant jump) to close.
    ref.listen<bool>(sidebarDrawerProvider, (previous, isOpen) {
      if (isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Fully closed and not animating — render nothing, so this overlay
        // never intercepts taps meant for the rail/content beneath it.
        if (_controller.isDismissed) return const SizedBox.shrink();
        return child!;
      },
      child: _buildOverlayContent(),
    );
  }

  Widget _buildOverlayContent() {
    return Stack(
      children: [
        // Backdrop starts right where the drawer ends, so it never competes
        // with the drawer panel for hit-testing.
        Positioned.fill(
          left: _drawerWidth,
          child: FadeTransition(
            opacity: _controller,
            child: GestureDetector(
              onTap: _close,
              child: Container(color: Colors.black.withValues(alpha: .35)),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _drawerWidth,
          child: SlideTransition(
            position: _slide,
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _close();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Material(
                elevation: 16,
                child: SidebarDrawer(currentPath: widget.currentPath),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Toast extends ConsumerWidget {
  const _Toast({required this.data});
  final ToastData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      liveRegion: true,
      label: data.message,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.navyDeep,
            borderRadius: AppRadius.smAll,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.message,
                style: AppTypography.chip
                    .copyWith(color: Colors.white, fontSize: 14.5),
              ),
              if (data.hasUndo) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    data.onUndo?.call();
                    ref.read(toastProvider.notifier).dismiss();
                  },
                  child: Text(
                    'UNDO',
                    style: AppTypography.chip.copyWith(
                      color: AppColors.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
