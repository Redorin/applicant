import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';

/// Off-screen link that's the first Tab stop in the app — slides into view
/// only once it (not the page content) receives keyboard focus. Activating
/// it (click, or Enter/Space while focused) moves focus to the main content
/// area, letting keyboard users skip the sidebar without tabbing through
/// every nav item first. Must be placed directly as a child of the same
/// `Stack` it should be positioned within (it builds to an
/// [AnimatedPositioned]) — in `AppShell` it's placed *last* among the
/// Stack's children so it paints on top once visible, which would normally
/// also put it last in Tab order; [FocusTraversalOrder] below overrides that
/// so it stays first regardless of its position in the tree.
class SkipToContentLink extends StatefulWidget {
  const SkipToContentLink({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  State<SkipToContentLink> createState() => _SkipToContentLinkState();
}

class _SkipToContentLinkState extends State<SkipToContentLink> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 150),
      left: 12,
      top: _focused ? 12 : -60,
      child: FocusTraversalOrder(
        order: const NumericFocusOrder(-1),
        child: Focus(
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              widget.onActivate();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onActivate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.actionBlue,
                  borderRadius: AppRadius.smAll,
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
                  ],
                ),
                child: const Text(
                  'Skip to content',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
