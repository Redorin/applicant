import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// The app's single light theme. There is no dark variant — this is a
/// government desktop app with one shared office login, not a per-user
/// preference worth maintaining two palettes for.
abstract final class AppTheme {
  static const fontFamily = 'Segoe UI';

  /// Keyboard-focus indicator applied to buttons/inputs on
  /// [WidgetState.focused] — a 2px accent outline distinct from the
  /// hover/pressed states, so Tab-navigating users can see where focus is.
  static const _focusRingSide = BorderSide(color: AppColors.actionBlue, width: 2);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.ground,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.light,
        seedColor: AppColors.actionBlue,
        primary: AppColors.actionBlue,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineMedium: AppTypography.pageTitle,
        titleMedium: AppTypography.dialogTitle,
        titleSmall: AppTypography.sectionTitle,
        bodyLarge: AppTypography.bodyStrong,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.helper,
        labelLarge: AppTypography.buttonLabel,
        labelMedium: AppTypography.fieldLabel,
        labelSmall: AppTypography.caption,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.actionBlue,
          foregroundColor: Colors.white,
          textStyle: AppTypography.buttonLabel,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return AppColors.actionBluePressed;
            if (states.contains(WidgetState.hovered)) return AppColors.actionBlueHover;
            return null;
          }),
          // Keyboard-focus indicator — a 2px accent outline distinct from
          // hover/pressed, so Tab-navigating users can see where focus is.
          side: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused) ? _focusRingSide : null),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line),
          textStyle: AppTypography.buttonLabel,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused)
              ? _focusRingSide
              : const BorderSide(color: AppColors.line)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: AppColors.inputEmptyBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: AppRadius.smAll, borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.smAll, borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.smAll, borderSide: _focusRingSide),
        labelStyle: AppTypography.fieldLabel.copyWith(letterSpacing: 0, fontWeight: FontWeight.w400),
        hintStyle: AppTypography.body.copyWith(color: AppColors.muted),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: const BorderSide(color: AppColors.line)),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: AppColors.navyDeep, borderRadius: AppRadius.smAll),
        textStyle: AppTypography.caption.copyWith(color: Colors.white),
      ),
      dialogTheme: DialogThemeData(
        titleTextStyle: AppTypography.dialogTitle,
        contentTextStyle: AppTypography.body,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),
    );
  }
}
