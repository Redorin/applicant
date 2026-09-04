import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The one shared type scale for the app. Every screen should reach for a
/// role here instead of a hand-picked `fontSize`. Roles are named for what
/// they're used for, not for a number, so the actual size can be tuned in
/// one place.
///
/// Colors are baked in for the common case; call sites needing a variant
/// (e.g. a danger-red label) use `.copyWith(color: ...)`.
abstract final class AppTypography {
  /// Screen-level page title, paired with [pageSubtitle] in a [PageHeader].
  static const pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// Muted line under a page title.
  static const pageSubtitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
  );

  /// Uppercase card/section header (e.g. AppCard title).
  static const sectionTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: .44,
    color: AppColors.muted,
  );

  /// Uppercase table column header (Applications table).
  static const tableHeader = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: .4,
    color: AppColors.muted,
  );

  /// Dialog / AlertDialog titles — wired into ThemeData.dialogTheme so most
  /// call sites don't need to set this explicitly at all.
  static const dialogTitle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// Uppercase field label above an input (Labeled).
  static const fieldLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: .4,
    color: Color(0xFF374151),
  );

  /// Default body / entered-value text.
  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
  );

  static const bodyStrong = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  /// Secondary/helper text — descriptions under section headers, hints.
  static const helper = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
  );

  /// Small meta text — status bar, timestamps, footer captions.
  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.muted,
  );

  /// Elevated/Outlined button label — wired into ThemeData button themes.
  static const buttonLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// Ghost/text-button label — lighter weight than [buttonLabel].
  static const ghostButtonLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  /// Large KPI figures on the dashboard.
  static const kpiNumber = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// Status pill / info chip / count badge text.
  static const chip = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  /// Sidebar nav item label.
  static const navLabel = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w500,
  );

  /// Sidebar footer version/org line.
  static const navCaption = TextStyle(
    fontSize: 12.5,
    height: 1.5,
  );
}
