import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// Named button-style variants that don't fit into a single global
/// ElevatedButtonTheme/OutlinedButtonTheme, replacing the per-screen
/// `OutlinedButton.styleFrom(...)` overrides that had accumulated.
abstract final class AppButtonStyles {
  /// Destructive outlined action (e.g. "Delete", confirm-dialog "Yes, remove").
  static final danger = OutlinedButton.styleFrom(
    foregroundColor: AppColors.danger,
    side: const BorderSide(color: AppColors.danger, width: 1.5),
    textStyle: AppTypography.buttonLabel,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
  ).copyWith(
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) return Colors.white;
      return AppColors.danger;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) return AppColors.danger;
      return Colors.transparent;
    }),
  );

  /// [danger]'s positive counterpart — bordered, ok-toned outlined action
  /// (e.g. table-row "Hire"). Same shape/padding/typography as [danger],
  /// just reusing the existing status-pill "ok" ink color instead of red.
  static final success = OutlinedButton.styleFrom(
    foregroundColor: AppColors.okInk,
    side: const BorderSide(color: AppColors.okInk, width: 1.5),
    textStyle: AppTypography.buttonLabel,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
  ).copyWith(
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) return Colors.white;
      return AppColors.okInk;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) return AppColors.okInk;
      return Colors.transparent;
    }),
  );

  /// Compact outlined button for toolbars/inline rows where the default
  /// button padding is too tall.
  static final compact = OutlinedButton.styleFrom(
    foregroundColor: AppColors.ink,
    side: const BorderSide(color: AppColors.line, width: 1.5),
    textStyle: AppTypography.buttonLabel,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
  ).copyWith(
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) return Colors.white;
      return AppColors.ink;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) return AppColors.muted;
      return Colors.transparent;
    }),
  );

  /// Borderless chrome-level action for a toolbar's secondary/navigation
  /// items — text only, so five-plus of them can sit side by side without
  /// reading as five competing buttons. Reserve bordered/filled styles for
  /// the toolbar's actual primary actions.
  static final chrome = TextButton.styleFrom(
    foregroundColor: AppColors.ink,
    textStyle: AppTypography.ghostButtonLabel,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
  ).copyWith(
    overlayColor: const WidgetStatePropertyAll(AppColors.selectionSoft),
  );

  /// Accent-outlined secondary CTA that sits next to a filled primary
  /// button (e.g. "Export to Excel" beside "Print Report…") — carries the
  /// same accent color so it still reads as related, without competing for
  /// the eye.
  static final tonal = OutlinedButton.styleFrom(
    foregroundColor: AppColors.actionBlue,
    side: const BorderSide(color: AppColors.actionBlue),
    textStyle: AppTypography.buttonLabel,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
  );

  /// Icon-only counterpart to [chrome] — same borderless/muted-ink/soft-hover
  /// look, for toolbars dense enough that labels are dropped in favor of a
  /// [Tooltip] on each icon.
  static final chromeIcon = IconButton.styleFrom(
    foregroundColor: AppColors.ink,
    padding: const EdgeInsets.all(10),
    minimumSize: const Size(36, 36),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
  ).copyWith(
    overlayColor: const WidgetStatePropertyAll(AppColors.selectionSoft),
  );

  /// Icon-only counterpart to [danger], bordered so a destructive action
  /// still stands out even without its label.
  static final dangerIcon = IconButton.styleFrom(
    foregroundColor: AppColors.danger,
    side: const BorderSide(color: AppColors.danger),
    padding: const EdgeInsets.all(10),
    minimumSize: const Size(36, 36),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
  );

  /// Borderless, gray-text toolbar action — same shape/hover as [chrome]
  /// but explicitly muted rather than ink, for secondary toolbar buttons
  /// that carry a visible text label (Recent, Settings, Import, Archived).
  static final ghost = TextButton.styleFrom(
    foregroundColor: const Color(0xFF374151),
    // Recent's button is intentionally always onPressed: null (the wrapping
    // PopupMenuButton handles the tap instead), which puts it in the
    // disabled WidgetState permanently — without this it falls back to
    // Material's generic ~38%-opacity disabled grey instead of matching
    // its enabled siblings (Settings/Import/Archived).
    disabledForegroundColor: const Color(0xFF374151),
    textStyle: AppTypography.ghostButtonLabel,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
  ).copyWith(
    overlayColor: const WidgetStatePropertyAll(AppColors.selectionSoft),
  );

  /// [ghost]'s destructive counterpart — borderless but red, for a toolbar
  /// "Archive" action that shouldn't compete visually with a bordered button.
  static final ghostDanger = TextButton.styleFrom(
    foregroundColor: AppColors.danger,
    textStyle: AppTypography.ghostButtonLabel,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
  ).copyWith(
    overlayColor: const WidgetStatePropertyAll(AppColors.dangerSoft),
  );

  /// Table row action icon (edit) — 28x28, accent-tinted hover.
  static final tableActionEdit = IconButton.styleFrom(
    foregroundColor: AppColors.actionBlue,
    padding: EdgeInsets.zero,
    minimumSize: const Size(28, 28),
    fixedSize: const Size(28, 28),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
  ).copyWith(
    overlayColor: const WidgetStatePropertyAll(AppColors.accentSoft),
  );

  /// Table row action icon (delete) — 28x28, danger-tinted hover.
  static final tableActionDelete = IconButton.styleFrom(
    foregroundColor: AppColors.danger,
    padding: EdgeInsets.zero,
    minimumSize: const Size(28, 28),
    fixedSize: const Size(28, 28),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
  ).copyWith(
    overlayColor: const WidgetStatePropertyAll(AppColors.dangerSoft),
  );
}
