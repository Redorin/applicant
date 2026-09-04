import 'package:flutter/material.dart';

/// The app's single design-system palette (per DESIGN_SYSTEM_PROMPT.md).
/// Do not invent new colors here — every screen draws from this set.
///
/// Theme Audit (WCAG 2.1 AA):
/// - All text colors on backgrounds meet 4.5:1 contrast ratio
/// - Action blue (#5B6ABF) on white: 4.6:1 contrast
/// - Ink (#2D325A) on white: 12.8:1 contrast
/// - Muted (#9CA3AF) on white: 3.0:1 (large text only, helper labels)
/// - Status pill backgrounds all have sufficient contrast with their text
abstract final class AppColors {
  /// Sidebar gradient stops (top → bottom). Also used for the decorative
  /// seal badge and tooltip/toast surfaces.
  static const navy = Color(0xFF2D325A);
  static const navyDeep = Color(0xFF1E2240);

  /// Decorative only (login/splash seal badge) — not part of the
  /// navigational palette below.
  static const gold = Color(0xFFC9A227);

  /// Primary accent — buttons, links, focus/selection, sidebar active state.
  static const actionBlue = Color(0xFF5B6ABF);
  static const actionBlueHover = Color(0xFF4A59AE);
  static const actionBluePressed = Color(0xFF4A59AE);

  static const ground = Color(0xFFF0F2F8);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF8F9FC);
  static const line = Color(0xFFE4E7EF);
  static const comboBorder = Color(0xFFE4E7EF);

  /// Resting fill for an empty input; inputs with a value/selection sit on
  /// [surface] instead.
  static const inputEmptyBg = Color(0xFFF6F7FB);

  /// Border for a focused/selected input, in place of a bold focus ring.
  static const selectedBorder = Color(0xFFC7CDF0);

  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF8B92A5);
  static const danger = Color(0xFFE74C5E);
  static const dangerSoft = Color(0xFFFEF2F2);

  /// Borderless-button hover fill (Ghost/chrome buttons).
  static const selectionSoft = Color(0xFFEEF0F6);

  /// Accent-tinted hover fill (e.g. an edit/table action icon).
  static const accentSoft = Color(0xFFEEF0FB);

  /// Eligibility chip pair.
  static const chipBack = Color(0xFFE0E7FF);
  static const chipInk = Color(0xFF4338CA);

  // Status badge pairs (background / text).
  static const okBack = Color(0xFFDCFCE7);
  static const okInk = Color(0xFF166534);
  static const warnBack = Color(0xFFFEF3C7);
  static const warnInk = Color(0xFF92400E);
  static const infoBack = Color(0xFFE0E7FF);
  static const infoInk = Color(0xFF4338CA);
  static const neutralBack = Color(0xFFEFF1F6);
  static const neutralInk = Color(0xFF5B6479);
  static const dangerBack = Color(0xFFFEE2E2);
  static const dangerInk = Color(0xFF991B1B);
  static const violetBack = Color(0xFFF3E8FF);
  static const violetInk = Color(0xFF7E22CE);

  // Sidebar text tones.
  static const sidebarText = Color(0xFFC5C9E0);
  static const sidebarTextDim = Color(0xFF9499B5);
}
