import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// Focus-ring wrapper for bespoke widgets that don't go through a Material
/// `ButtonStyle` (see AppTheme's elevatedButtonTheme/outlinedButtonTheme for
/// the equivalent on standard buttons/inputs, which paint their own 2px
/// accent border on [WidgetState.focused]). Paints the same 2px accent
/// border around [child] whenever it has focus.
///
/// [onActivate], if given, also makes [child] keyboard-operable — a plain
/// `GestureDetector` (e.g. `_RailIconButton`'s tap target) isn't focusable
/// or Enter/Space-activatable on its own, so wrapping it here does both:
/// visible focus + real keyboard operability, not just a coat of paint.
class KeyboardFocusRing extends StatefulWidget {
  const KeyboardFocusRing({
    super.key,
    required this.child,
    this.borderRadius,
    this.onActivate,
  });

  final Widget child;
  final BorderRadiusGeometry? borderRadius;
  final VoidCallback? onActivate;

  @override
  State<KeyboardFocusRing> createState() => _KeyboardFocusRingState();
}

class _KeyboardFocusRingState extends State<KeyboardFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: widget.onActivate == null
          ? null
          : (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space)) {
                widget.onActivate!();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: _focused ? Border.all(color: AppColors.actionBlue, width: 2) : null,
        ),
        child: widget.child,
      ),
    );
  }
}
