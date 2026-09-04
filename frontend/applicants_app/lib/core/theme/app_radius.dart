import 'package:flutter/material.dart';

/// Shared corner-radius scale — replaces the 10 unrelated radius values
/// (1, 3, 4, 5, 6, 7, 8, 9, 10, 20) that had accumulated across screens.
abstract final class AppRadius {
  /// Inputs, buttons, small chips.
  static const sm = 6.0;

  /// Cards, panels.
  static const md = 10.0;

  /// Dialogs and larger surfaces.
  static const lg = 12.0;

  /// Status badges, chips.
  static const pill = 10.0;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}
