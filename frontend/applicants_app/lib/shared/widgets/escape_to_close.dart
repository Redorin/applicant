import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps dialog content so pressing Escape pops it — lifted from the same
/// pattern already used by the sidebar drawer overlay (see app_shell.dart's
/// `_DrawerOverlay` Escape handler), generalized to any dialog's Navigator.
class EscapeToClose extends StatelessWidget {
  const EscapeToClose({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
