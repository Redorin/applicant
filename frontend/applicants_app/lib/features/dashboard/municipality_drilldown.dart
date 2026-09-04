import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/status_color.dart';
import '../applicant_browse/applicant_browse_provider.dart';
import '../auth/auth_provider.dart';
import 'dashboard_provider.dart';
import 'dashboard_screen.dart' show goFiltered;

final _drilldownPreviewProvider =
    FutureProvider.autoDispose.family<List<BrowseRow>, String>((ref, municipality) async {
  final period = ref.watch(dashboardPeriodProvider);
  final bounds = periodBounds(period);
  final filters = BrowseFilters(
      municipality: municipality, dateFrom: bounds.from, dateTo: bounds.to);
  final api = ref.read(apiClientProvider);
  final json = await api
          .get('/api/browse/?${filters.toQuery(false, overridePageSize: 8)}')
      as Map<String, dynamic>;
  return (json['rows'] as List)
      .map((e) => BrowseRow.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// A quick preview of one municipality's applicants for the selected
/// dashboard period, with a one-click handoff to the full filtered list —
/// a lighter alternative to jumping straight to Browse for every click.
Future<void> showMunicipalityDrilldown(BuildContext outerContext, WidgetRef ref,
    String municipality, int count) {
  // Bind "View full list" to the exact same window the modal's count and
  // preview came from — "all time" means truly unbounded (Any time), not
  // the wide sentinel dates used internally to keep the SQL shape simple.
  final period = ref.read(dashboardPeriodProvider);
  final bounds = period == 'all' ? null : periodBounds(period);

  return showDialog(
    context: outerContext,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(municipality, style: AppTypography.dialogTitle),
              const SizedBox(height: 2),
              Text('$count applications in the selected period',
                  style: AppTypography.helper),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Flexible(
                child: Consumer(
                  builder: (context, ref, _) {
                    final preview =
                        ref.watch(_drilldownPreviewProvider(municipality));
                    return preview.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                            child: SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))),
                      ),
                      error: (e, _) => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('Could not load a preview.',
                            style: AppTypography.helper),
                      ),
                      data: (rows) => rows.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text('No applicants to preview.',
                                  style: AppTypography.helper),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: rows.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 12),
                              itemBuilder: (context, i) {
                                final r = rows[i];
                                final pal = statusPaletteFor(r.status);
                                return Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(r.applicant, style: AppTypography.bodyStrong),
                                          Text(
                                            r.appDate == null
                                                ? (r.position ?? '')
                                                : '${DateFormat('MMM d, yyyy').format(r.appDate!)} · ${r.position ?? ''}',
                                            style: AppTypography.caption,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if ((r.status ?? '').trim().isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: pal.background,
                                          borderRadius: AppRadius.pillAll,
                                        ),
                                        child: Text(r.status!,
                                            style: AppTypography.chip.copyWith(color: pal.ink)),
                                      ),
                                  ],
                                );
                              },
                            ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('View full list'),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      goFiltered(outerContext, ref,
                          municipality: municipality,
                          dateFrom: bounds?.from,
                          dateTo: bounds?.to);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
