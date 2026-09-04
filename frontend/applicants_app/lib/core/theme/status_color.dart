import 'package:flutter/material.dart';
import 'app_colors.dart';

/// The one canonical status → color rule, identical to the old app's
/// Theme.MakePillColumn / dashboard.StatusFill keyword matching.
/// Every screen that renders a status calls this — never re-implement the match.
class StatusPalette {
  const StatusPalette(this.background, this.ink);
  final Color background;
  final Color ink;
}

StatusPalette statusPaletteFor(String? status) {
  final probe = (status ?? '').toLowerCase();
  if (probe.contains('hire')) {
    return const StatusPalette(AppColors.okBack, AppColors.okInk);
  }
  if (probe.contains('re-application') ||
      probe.contains('reapplication') ||
      probe.contains('reapply')) {
    return const StatusPalette(AppColors.infoBack, AppColors.infoInk);
  }
  if (probe.contains('interview') ||
      probe.contains('pending') ||
      probe.contains('process') ||
      probe.contains('review')) {
    return const StatusPalette(AppColors.warnBack, AppColors.warnInk);
  }
  if (probe.contains('reject')) {
    return const StatusPalette(AppColors.dangerBack, AppColors.dangerInk);
  }
  return const StatusPalette(AppColors.neutralBack, AppColors.neutralInk);
}
