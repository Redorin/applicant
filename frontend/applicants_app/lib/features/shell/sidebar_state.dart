import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data_health/data_health_screen.dart';
import '../master_data/unsaved_guard.dart';

/// Whether the overlay drawer is open. Ephemeral — unlike the old
/// push-collapse sidebar's persisted width preference, an overlay drawer
/// has no business surviving an app restart open, so this is a plain
/// in-memory Notifier (same shape as [toastProvider] in toast_provider.dart)
/// rather than anything backed by SharedPreferences.
class SidebarDrawerController extends Notifier<bool> {
  @override
  bool build() => false;

  void open() => state = true;
  void close() => state = false;
  void toggle() => state = !state;
}

final sidebarDrawerProvider =
    NotifierProvider<SidebarDrawerController, bool>(SidebarDrawerController.new);

/// Data Health's "needs attention" count — not fabricating badges for
/// sections that don't have one. Two of its five categories
/// (invalid-contacts, legacy-eligibility) flag bulk historical debt by
/// design — tens of thousands of legacy rows, not things to act on today —
/// so they're excluded to keep the badge a genuine "here's a handful of
/// things to check" signal. Exposed as its own provider so the rail's dot
/// and the drawer's numbered pill always read the exact same value.
final healthBadgeTotalProvider = Provider<int>((ref) {
  const bulkLegacyCategories = {'invalid-contacts', 'legacy-eligibility'};
  return ref.watch(healthSummaryProvider).maybeWhen(
        data: (cats) => cats
            .where((c) => !bulkLegacyCategories.contains(c.key))
            .fold<int>(0, (sum, c) => sum + c.count),
        orElse: () => 0,
      );
});

/// Shared nav-tap handling for every sidebar item except Preferences (which
/// intentionally bypasses the unsaved-changes guard, matching its existing
/// behavior). Used identically by both the rail and the drawer so the guard
/// can never drift between the two. Does not force-close the drawer — the
/// hover zone (see [_SidebarHoverZone] in app_shell.dart) already owns that,
/// since the cursor is typically still inside the drawer when a row is
/// clicked.
Future<void> handleNavTap(
  BuildContext context,
  WidgetRef ref, {
  required String currentPath,
  required String targetPath,
}) async {
  // Leaving Master Data with unsaved edits prompts first.
  if (currentPath.startsWith('/master-data') &&
      !targetPath.startsWith('/master-data')) {
    final ok = await resolveUnsavedChanges(context, ref);
    if (!ok) return;
  }
  if (context.mounted) context.go(targetPath);
}
