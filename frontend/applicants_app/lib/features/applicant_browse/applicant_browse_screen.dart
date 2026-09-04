import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_button_styles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/status_color.dart';
import '../../shared/widgets/hover_scale.dart';
import '../../shared/widgets/initial_avatar.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/shimmer.dart';
import '../auth/auth_provider.dart';
import '../dashboard/dashboard_provider.dart';
import '../data_health/statuses_provider.dart';
import '../lookups/lookups_provider.dart';
import '../master_data/widgets/form_bits.dart';
import '../reports/report_criteria_dialog.dart';
import '../reports/report_preview.dart';
import '../reports/reports_provider.dart';
import '../shell/toast_provider.dart';
import 'applicant_browse_provider.dart';
import 'browse_column_prefs_provider.dart';
import 'browse_export_writer.dart';
import 'export_modal.dart';

class _HireInput {
  const _HireInput(this.finalPosition, this.dateHired);
  final String finalPosition;
  final DateTime dateHired;
}

/// Prompts for the two things Hire requires: final position (free text) and
/// date hired (always user-entered — never defaulted to "today").
Future<_HireInput?> _showHireDialog(BuildContext context,
    {required String applicantName}) {
  final positionController = TextEditingController();
  DateTime? dateHired;

  return showDialog<_HireInput>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final fmt = DateFormat('MMM dd, yyyy');
        final canSave = positionController.text.trim().isNotEmpty && dateHired != null;
        return AlertDialog(
          title: Text('Hire $applicantName'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Labeled(
                  label: 'Final position',
                  required: true,
                  child: TextField(
                    controller: positionController,
                    style: kValueStyle,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 12),
                Labeled(
                  label: 'Date hired',
                  required: true,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.date_range_outlined, size: 15),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.comboBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      alignment: Alignment.centerLeft,
                    ),
                    label: Text(
                      dateHired == null ? 'Select date…' : fmt.format(dateHired!),
                      style: AppTypography.body,
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2005),
                        lastDate: DateTime.now(),
                        initialDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => dateHired = picked);
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: canSave
                  ? () => Navigator.pop(
                      ctx, _HireInput(positionController.text.trim(), dateHired!))
                  : null,
              child: const Text('Hire'),
            ),
          ],
        );
      },
    ),
  );
}

/// One screen serving both "List of Applicants" (hiredOnly=false) and
/// "Hired Applicants" (hiredOnly=true), like the old applicantbrowse.cs.
class ApplicantBrowseScreen extends ConsumerStatefulWidget {
  const ApplicantBrowseScreen({super.key, required this.hiredOnly});

  final bool hiredOnly;

  @override
  ConsumerState<ApplicantBrowseScreen> createState() =>
      _ApplicantBrowseScreenState();
}

class _ApplicantBrowseScreenState extends ConsumerState<ApplicantBrowseScreen> {
  late final TextEditingController _name;
  late final TextEditingController _status;
  Timer? _debounce;

  /// Application ids checked in the results grid — cleared whenever the
  /// filters/page change so a stale selection from a different view can't
  /// silently carry over.
  final Set<int> _selectedIds = {};

  /// Rows that should play a brief red-flash animation (after reject).
  final Set<int> _flashingRows = {};

  @override
  void initState() {
    super.initState();
    final filters = ref.read(browseFiltersProvider(widget.hiredOnly));
    _name = TextEditingController(text: filters.name);
    _status = TextEditingController(text: filters.status);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _status.dispose();
    super.dispose();
  }

  void _applyDebounced(BrowseFilters Function(BrowseFilters) change) {
    _debounce?.cancel();
    // Same 400ms debounce as the old app's filter bar.
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final notifier = ref.read(browseFiltersProvider(widget.hiredOnly).notifier);
      notifier.update(change(ref.read(browseFiltersProvider(widget.hiredOnly))));
      if (_selectedIds.isNotEmpty) setState(_selectedIds.clear);
    });
  }

  void _applyNow(BrowseFilters Function(BrowseFilters) change) {
    final notifier = ref.read(browseFiltersProvider(widget.hiredOnly).notifier);
    notifier.update(change(ref.read(browseFiltersProvider(widget.hiredOnly))));
    if (_selectedIds.isNotEmpty) setState(_selectedIds.clear);
  }

  Future<void> _reject(BrowseRow row) async {
    if (row.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this application?'),
        content: Text('${row.applicant} will be marked as Rejected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final api = ref.read(apiClientProvider);
    final previousStatus = row.status;

    try {
      // Reject on the server first.
      await applyBulkStatus(api, [row.id!], 'Rejected');

      // Optimistic update: set status locally so the UI updates immediately.
      row.status = 'Rejected';

      // Flash the row red briefly.
      setState(() => _flashingRows.add(row.id!));
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _flashingRows.remove(row.id!));
      });

      // Show undo toast.
      ref.read(toastProvider.notifier).showUndo(
            '${row.applicant} marked as Rejected.',
            () async {
              // Undo: revert on the server and locally.
              try {
                await applyBulkStatus(api, [row.id!], previousStatus ?? 'On Process');
                row.status = previousStatus;
                if (mounted) setState(() {});
              } on ApiException catch (e) {
                if (mounted) {
                  ref.read(toastProvider.notifier).show('Undo failed: ${e.message}');
                }
              }
            },
          );

      Sentry.addBreadcrumb(Breadcrumb(
        category: 'applicant',
        message: 'Application rejected',
        data: {'applicantId': row.id, 'applicant': row.applicant},
      ));
    } on ApiException catch (e) {
      if (mounted) ref.read(toastProvider.notifier).show(e.message);
    }
  }


  // Hiring/unhiring moves a row between the two tabs (they're a strict
  // partition on hired_date server-side), so both result sets need to
  // refetch — not just this screen's own.
  void _refreshBothTabs() {
    ref.invalidate(browseResultsProvider(true));
    ref.invalidate(browseResultsProvider(false));
  }

  Future<void> _hire(BrowseRow row) async {
    final input = await _showHireDialog(context, applicantName: row.applicant);
    if (input == null || !mounted) return;

    final api = ref.read(apiClientProvider);
    try {
      await api.post('/api/applications/${row.id}/hire', body: {
        'finalPosition': input.finalPosition,
        'finalDepartment': row.department,
        'dateHired': input.dateHired.toIso8601String(),
      });
      _refreshBothTabs();
      Sentry.addBreadcrumb(Breadcrumb(
        category: 'applicant',
        message: 'Applicant hired',
        data: {
          'applicantId': row.id,
          'applicant': row.applicant,
          'finalPosition': input.finalPosition,
        },
      ));
      if (mounted) {
        ref.read(toastProvider.notifier).show('${row.applicant} marked as hired.');
      }
    } on ApiException catch (e) {
      if (mounted) ref.read(toastProvider.notifier).show(e.message);
    }
  }

  Future<void> _unhire(BrowseRow row) async {
    final result = await showDialog<_UnhireResult>(
      context: context,
      builder: (ctx) => _UnhireDialog(row: row),
    );
    if (result == null || !mounted) return;

    final api = ref.read(apiClientProvider);
    final previousHiredDate = row.hiredDate;
    final previousFinalPosition = row.finalPosition;
    final previousFinalDepartment = row.finalDepartment;

    try {
      await api.post('/api/applications/${row.id}/unhire', body: {
        if (result.status != null) 'status': result.status,
      });

      // Optimistic update: clear hiring fields locally.
      row.hiredDate = null;
      row.finalPosition = null;
      row.finalDepartment = null;
      if (result.status != null) row.status = result.status;

      // Flash the row briefly (green tint for "moved back").
      setState(() => _flashingRows.add(row.id!));
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _flashingRows.remove(row.id!));
      });

      // Refresh both tabs (row moves from Hired to List).
      _refreshBothTabs();

      // Show undo toast.
      ref.read(toastProvider.notifier).showUndo(
            '${row.applicant} moved back to List of Applicants.',
            () {
              // Undo: revert the optimistic update locally.
              // The row will appear on Hired tab after refresh.
              row.hiredDate = previousHiredDate;
              row.finalPosition = previousFinalPosition;
              row.finalDepartment = previousFinalDepartment;
              if (result.status != null) row.status = row.status;
              _refreshBothTabs();
              if (mounted) setState(() {});
            },
          );

      Sentry.addBreadcrumb(Breadcrumb(
        category: 'applicant',
        message: 'Applicant unhired',
        data: {'applicantId': row.id, 'applicant': row.applicant},
      ));
    } on ApiException catch (e) {
      if (mounted) ref.read(toastProvider.notifier).show(e.message);
    }
  }

  // "Export" (toolbar) generates the same PDF report the old "Print Report…"
  // button did — that button was removed when the toolbar was simplified,
  // and its behavior now lives under the Export label/icon instead.
  Future<void> _exportReport() async {
    final lookups = await ref.read(lookupsProvider.future);
    if (!mounted) return;
    final criteria = await showReportCriteriaDialog(
      context,
      hired: widget.hiredOnly,
      lookups: lookups,
      statusSuggestions: ref.read(statusNamesProvider),
    );
    if (criteria == null || !mounted) return;
    ref.read(toastProvider.notifier).show('Generating report…');
    try {
      final bytes = await ref.read(reportRunnerProvider).fetchPdf(
            widget.hiredOnly ? '/api/reports/hired' : '/api/reports/list',
            body: criteria.toJson(),
          );
      if (mounted && context.mounted) {
        await showReportPreview(context, ref,
            bytes: bytes,
            suggestedFileName:
                widget.hiredOnly ? 'hired-applicants.pdf' : 'list-of-applicants.pdf');
      }
    } catch (_) {
      if (mounted) {
        ref.read(toastProvider.notifier).show('Unable to produce the report');
      }
    }
  }

  /// Opens the format/scope/options modal. PDF still runs the existing
  /// [_exportReport] pipeline unchanged; Excel/CSV are real exports via
  /// browse_export_writer.dart, sourced by the chosen scope.
  Future<void> _exportViaModal(BrowsePage page) async {
    final choice = await showExportModal(context, hasSelection: _selectedIds.isNotEmpty);
    if (choice == null || !mounted) return;

    if (choice.format == ExportFormat.pdf) {
      await _exportReport();
      return;
    }

    ref.read(toastProvider.notifier).show('Preparing export…');
    final api = ref.read(apiClientProvider);
    final filters = ref.read(browseFiltersProvider(widget.hiredOnly));
    try {
      final rows = switch (choice.scope) {
        ExportScope.selected =>
          page.rows.where((r) => r.id != null && _selectedIds.contains(r.id)).toList(),
        ExportScope.filtered => await fetchAllBrowseRows(api, filters, widget.hiredOnly),
        ExportScope.all =>
          await fetchAllBrowseRows(api, filters, widget.hiredOnly, ignoreFilters: true),
      };
      if (!mounted) return;
      final baseName = widget.hiredOnly ? 'hired-applicants' : 'list-of-applicants';
      final saved = choice.format == ExportFormat.excel
          ? await exportRowsToExcel(
              rows,
              hiredOnly: widget.hiredOnly,
              includeHeaderRow: choice.includeHeaderRow,
              includeTimestamps: choice.includeTimestamps,
              suggestedFileName: '$baseName.xlsx',
            )
          : await exportRowsToCsv(
              rows,
              hiredOnly: widget.hiredOnly,
              includeHeaderRow: choice.includeHeaderRow,
              includeTimestamps: choice.includeTimestamps,
              suggestedFileName: '$baseName.csv',
            );
      if (mounted && saved) {
        ref.read(toastProvider.notifier).show('Exported ${rows.length} row(s)');
      }
    } on ApiException catch (e) {
      if (mounted) ref.read(toastProvider.notifier).show(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(browseFiltersProvider(widget.hiredOnly));
    final results = ref.watch(browseResultsProvider(widget.hiredOnly));
    final fmt = DateFormat('MMM dd, yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: PageHeader(
            title: widget.hiredOnly ? 'Hired Applicants' : 'List of Applicants',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, AppSpacing.md, 18, 0),
          child: _StatsRow(hiredOnly: widget.hiredOnly),
        ),
        // ---- filter bar ----
        Container(
          margin: const EdgeInsets.fromLTRB(18, AppSpacing.md, 18, 0),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.lgAll,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 220,
                height: 42,
                child: TextField(
                  controller: _name,
                  style: kValueStyle.copyWith(fontSize: 13),
                  decoration: kInputDecoration.copyWith(
                    hintText: 'Search applicants…',
                    prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.muted),
                  ),
                  onChanged: (v) =>
                      _applyDebounced((f) => f.copyWith(name: v)),
                ),
              ),
              const Spacer(),
              if (!widget.hiredOnly) ...[
                SizedBox(
                  width: 170,
                  height: 42,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final names = ref.watch(statusNamesProvider);
                      return SearchableDropdown(
                        options: names,
                        value: _status.text.isEmpty ? null : _status.text,
                        hint: 'All Status',
                        allowClear: false,
                        onChanged: (v) {
                          _status.text = v ?? '';
                          _applyNow((f) => f.copyWith(status: v ?? ''));
                        },
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(width: 10),
              SizedBox(
                width: 190,
                height: 42,
                child: Consumer(
                  builder: (context, ref, _) {
                    final lookups = ref.watch(lookupsProvider);
                    return lookups.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (l) => SearchableDropdown(
                        options: l.departments,
                        value: filters.office,
                        hint: 'All Offices',
                        allowClear: false,
                        onChanged: (v) => _applyNow((f) => v == null
                            ? f.copyWith(clearOffice: true)
                            : f.copyWith(office: v)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              _FilterPanelButton(
                hiredOnly: widget.hiredOnly,
                onClearFilters: () {
                  _name.clear();
                  _status.clear();
                  ref
                      .read(browseFiltersProvider(widget.hiredOnly).notifier)
                      .clear();
                },
              ),
              const SizedBox(width: 8),
              HoverScale(
                glow: true,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Export'),
                  onPressed: results.maybeWhen(
                    data: (page) =>
                        page.rows.isEmpty ? null : () => _exportViaModal(page),
                    orElse: () => null,
                  ),
                ),
              ),
            ],
          ),
        ),
        // ---- results grid ----
        Expanded(
          child: results.when(
            loading: () => Container(
              margin: const EdgeInsets.fromLTRB(18, 12, 18, 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: _SkeletonResultsGrid(hiredOnly: widget.hiredOnly),
            ),
            error: (e, _) => Center(
              child: Text('Could not load applicants: $e', style: AppTypography.helper),
            ),
            data: (page) => page.rows.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off_outlined,
                            size: 44, color: AppColors.muted),
                        const SizedBox(height: 10),
                        Text('No matching applicants',
                            style: AppTypography.bodyStrong.copyWith(fontSize: 17)),
                        const SizedBox(height: 4),
                        const Text('Try adjusting your filters.', style: AppTypography.helper),
                      ],
                    ),
                  )
                : Container(
                    margin: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(color: AppColors.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _ResultsGrid(
                        rows: page.rows,
                        hiredOnly: widget.hiredOnly,
                        dateFormat: fmt,
                        sortBy: filters.sortBy,
                        sortDir: filters.sortDir,
                        onSort: (column) => ref
                            .read(browseFiltersProvider(widget.hiredOnly)
                                .notifier)
                            .update(filters.toggleSort(column)),
                        hidden: ref.watch(browseColumnPrefsProvider),
                        onHire: _hire,
                        onUnhire: _unhire,
                        onReject: _reject,
                        flashingIds: _flashingRows,
                        selectedIds: _selectedIds,
                        onToggleRow: (id, selected) => setState(() {
                              if (selected) {
                                _selectedIds.add(id);
                              } else {
                                _selectedIds.remove(id);
                              }
                            }),
                        onToggleAll: (selected) => setState(() {
                              final ids = page.rows
                                  .map((r) => r.id)
                                  .whereType<int>();
                              if (selected) {
                                _selectedIds.addAll(ids);
                              } else {
                                _selectedIds.removeAll(ids);
                              }
                            })),
                  ),
          ),
        ),
        // ---- pager ----
        results.maybeWhen(
          data: (page) => _Pager(
            currentPage: filters.page,
            total: page.total,
            onGoTo: (p) => _applyNow((f) => f.copyWith(page: p)),
          ),
          orElse: () => const SizedBox(height: 8),
        ),
      ],
    );
  }
}

/// "Filters" trigger opening a popover with the less-used filters
/// (Municipality/Office/Course/Eligibility/Date applied range) plus "Clear
/// filters" — keeps the always-visible bar to one fixed row instead of
/// scrolling.
///
/// This is NOT built as a hand-rolled `OverlayEntry` (unlike
/// [ColumnVisibilityButton]) — [SearchableDropdown] wraps Flutter's
/// `DropdownMenu`, which manages its own overlay-anchored menu. Nesting that
/// inside a second, manually-managed `OverlayEntry` produced a
/// `debugNeedsLayout` assertion crash and made the dropdowns unresponsive,
/// because the two overlay/layout passes fought each other. Presenting the
/// panel with `showDialog` instead routes it through the same
/// Navigator-owned overlay `DropdownMenu` and `showDateRangePicker` already
/// use elsewhere in this screen without conflict.
class _FilterPanelButton extends StatelessWidget {
  const _FilterPanelButton(
      {required this.hiredOnly, required this.onClearFilters});
  final bool hiredOnly;
  final VoidCallback onClearFilters;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final anchor = box.localToGlobal(Offset(0, box.size.height + 6));
    final screenWidth = MediaQuery.of(context).size.width;
    const panelWidth = 320.0;
    // Flip to left side if it would overflow the right edge.
    final left = anchor.dx + panelWidth > screenWidth
        ? screenWidth - panelWidth - 16
        : anchor.dx;
    final fmt = DateFormat('MMM dd, yyyy');

    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => Stack(
        children: [
          Positioned(
            left: left,
            top: anchor.dy,
            child: Material(
              elevation: 6,
              borderRadius: AppRadius.mdAll,
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: AppRadius.mdAll,
                ),
                child: Consumer(
                  builder: (context, ref, _) {
                    final filters =
                        ref.watch(browseFiltersProvider(hiredOnly));
                    final municipalities =
                        ref.watch(browseMunicipalitiesProvider);
                    final lookups = ref.watch(lookupsProvider);

                    void applyNow(BrowseFilters Function(BrowseFilters) c) {
                      ref
                          .read(browseFiltersProvider(hiredOnly).notifier)
                          .update(c(filters));
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Labeled(
                          label: 'Municipality',
                          child: municipalities.when(
                            loading: () => const SizedBox(
                                height: 30,
                                child: Center(
                                    child: SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)))),
                            error: (_, _) => const Text('—'),
                            data: (list) => SearchableDropdown(
                              options: list,
                              value: filters.municipality,
                              hint: 'All',
                              onChanged: (v) => applyNow((f) => v == null
                                  ? f.copyWith(clearMunicipality: true)
                                  : f.copyWith(municipality: v)),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Labeled(
                          label: 'Course',
                          child: lookups.when(
                            loading: () => const SizedBox(
                                height: 30,
                                child: Center(
                                    child: SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)))),
                            error: (_, _) => const Text('—'),
                            data: (l) => SearchableDropdown(
                              options: l.education,
                              value: filters.course,
                              hint: 'All',
                              onChanged: (v) => applyNow((f) => v == null
                                  ? f.copyWith(clearCourse: true)
                                  : f.copyWith(course: v)),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Labeled(
                          label: 'Eligibility',
                          child: lookups.when(
                            loading: () => const SizedBox(
                                height: 30,
                                child: Center(
                                    child: SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)))),
                            error: (_, _) => const Text('—'),
                            data: (l) => SearchableDropdown(
                              options: l.eligibilities,
                              value: filters.eligibility,
                              hint: 'All',
                              onChanged: (v) => applyNow((f) => v == null
                                  ? f.copyWith(clearEligibility: true)
                                  : f.copyWith(eligibility: v)),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Labeled(
                          label: 'Recommendation',
                          child: lookups.when(
                            loading: () => const SizedBox(
                                height: 30,
                                child: Center(
                                    child: SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)))),
                            error: (_, _) => const Text('—'),
                            data: (l) {
                              final officerNames = l.officers.map((o) => o.recommending).toList();
                              return SearchableDropdown(
                                options: officerNames,
                                value: filters.recommendation,
                                hint: 'All',
                                onChanged: (v) => applyNow((f) => v == null
                                    ? f.copyWith(clearRecommendation: true)
                                    : f.copyWith(recommendation: v)),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Labeled(
                          label: 'Date applied range',
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.date_range_outlined,
                                size: 15),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: AppColors.comboBorder),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 12),
                              alignment: Alignment.centerLeft,
                            ),
                            label: Text(
                              filters.dateFrom == null
                                  ? 'Any time'
                                  : '${fmt.format(filters.dateFrom!)} – ${filters.dateTo == null ? '…' : fmt.format(filters.dateTo!)}',
                              style: AppTypography.body,
                            ),
                            onPressed: () async {
                              final now = DateTime.now();
                              final range = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2005),
                                lastDate: DateTime(now.year, 12, 31),
                                initialDateRange: filters.dateFrom == null
                                    ? null
                                    : DateTimeRange(
                                        start: filters.dateFrom!,
                                        end: filters.dateTo ?? now),
                              );
                              if (range != null) {
                                applyNow((f) => f.copyWith(
                                    dateFrom: range.start,
                                    dateTo: range.end));
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton.icon(
                          style: AppButtonStyles.chrome,
                          icon: const Icon(Icons.filter_alt_off_outlined,
                              size: 16),
                          label: const Text('Clear filters'),
                          onPressed: filters.isEmpty
                              ? null
                              : () {
                                  onClearFilters();
                                  Navigator.of(dialogContext).pop();
                                },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: AppButtonStyles.ghost,
      icon: const Icon(Icons.settings_outlined, size: 16),
      label: const Text('Filters'),
      onPressed: () => _open(context),
    );
  }
}

/// Mirrors [_ResultsGrid]'s real header + 54px row height exactly, so
/// swapping to real data doesn't reflow the grid.
class _SkeletonResultsGrid extends StatelessWidget {
  const _SkeletonResultsGrid({required this.hiredOnly});
  final bool hiredOnly;

  @override
  Widget build(BuildContext context) {
    Widget h(String label, {int flex = 1}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(label, style: AppTypography.sectionTitle),
          ),
        );

    return Column(
      children: [
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFFAFBFD),
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(children: [
            const SizedBox(width: 36),
            h('APPLICANT', flex: 3),
            h('MUNICIPALITY', flex: 2),
            if (!hiredOnly) ...[
              h('POSITION APPLIED', flex: 2),
              h('OFFICE', flex: 3),
            ] else ...[
              h('DATE HIRED', flex: 2),
              h('FINAL POSITION', flex: 2),
            ],
            h('STATUS', flex: 2),
            h('ACTION', flex: 2),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: 10,
            itemExtent: 54,
            itemBuilder: (context, i) => _SkeletonRowTile(striped: i.isOdd),
          ),
        ),
      ],
    );
  }
}

class _SkeletonRowTile extends StatelessWidget {
  const _SkeletonRowTile({required this.striped});
  final bool striped;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: striped ? const Color(0xFFF8F9FC) : AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const SizedBox(width: 36),
          const Expanded(
            flex: 3,
            child: Row(
              children: [
                SkeletonBox(
                  width: 28,
                  height: 28,
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 110, height: 12),
                      SizedBox(height: 5),
                      SkeletonBox(width: 70, height: 9),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(flex: 2, child: SkeletonBox(width: 80, height: 12)),
          const SizedBox(width: 8),
          const Expanded(flex: 2, child: SkeletonBox(width: 60, height: 12)),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SkeletonBox(width: 50, height: 20, borderRadius: AppRadius.pillAll),
          ),
          const SizedBox(width: 8),
          const Expanded(flex: 2, child: SkeletonBox(width: 60, height: 24)),
        ],
      ),
    );
  }
}

/// Virtualized results grid — only visible rows are built, so 1,000-row
/// result sets render instantly (DataTable builds every row up front).
class _ResultsGrid extends StatelessWidget {
  const _ResultsGrid({
    required this.rows,
    required this.hiredOnly,
    required this.dateFormat,
    this.sortBy,
    this.sortDir = 'desc',
    this.onSort,
    this.hidden = const {},
    this.onHire,
    this.onUnhire,
    this.onReject,
    this.flashingIds = const {},
    this.selectedIds = const {},
    this.onToggleRow,
    this.onToggleAll,
  });
  final List<BrowseRow> rows;
  final bool hiredOnly;
  final DateFormat dateFormat;

  /// Current sort column (null = server default) and direction, plus the
  /// callback fired when a sortable header is tapped.
  final String? sortBy;
  final String sortDir;
  final ValueChanged<String>? onSort;

  /// Column keys hidden via the Columns toggle. Applicant is never in here.
  final Set<String> hidden;

  /// Row action handlers — Hire/Reject show on the List tab, Unhire on the
  /// Hired tab. Not part of `hidden`: this column is always shown.
  final ValueChanged<BrowseRow>? onHire;
  final ValueChanged<BrowseRow>? onUnhire;
  final ValueChanged<BrowseRow>? onReject;

  /// Row ids that should play a brief red-flash animation (after reject).
  final Set<int> flashingIds;

  /// Row-selection checkboxes, backing the bulk-status-update action bar.
  final Set<int> selectedIds;
  final void Function(int id, bool selected)? onToggleRow;
  final ValueChanged<bool>? onToggleAll;

  static const _colCheckbox = 36.0;

  @override
  Widget build(BuildContext context) {
    final selectableIds = rows.map((r) => r.id).whereType<int>().toSet();
    final allSelected = selectableIds.isNotEmpty &&
        selectableIds.every(selectedIds.contains);

    return Column(
      children: [
        _headerRow(allSelected),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: 54,
            itemBuilder: (context, i) =>
                _BrowseRowTile(
                  row: rows[i],
                  hiredOnly: hiredOnly,
                  dateFormat: dateFormat,
                  striped: i.isOdd,
                  hidden: hidden,
                  onHire: onHire,
                  onUnhire: onUnhire,
                  onReject: onReject,
                  isFlashing: rows[i].id != null &&
                      flashingIds.contains(rows[i].id),
                  selected: rows[i].id != null &&
                      selectedIds.contains(rows[i].id),
                  onToggleSelected: onToggleRow,
                ),
          ),
        ),
      ],
    );
  }

  Widget _headerRow(bool allSelected) {
    Widget h(String label, {int flex = 1}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(label, style: AppTypography.sectionTitle),
          ),
        );

    // Only columns the backend actually knows how to sort by are tappable.
    Widget sortable(String label, String column, {int flex = 1}) {
      final active = sortBy == column;
      final content = Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppTypography.sectionTitle.copyWith(
                    color: active ? AppColors.ink : AppColors.muted)),
            if (active) ...[
              const SizedBox(width: 3),
              Icon(
                sortDir == 'asc' ? Icons.arrow_upward : Icons.arrow_downward,
                size: 11,
                color: AppColors.ink,
              ),
            ],
          ],
        ),
      );
      if (onSort == null) return Expanded(flex: flex, child: content);
      return Expanded(
        flex: flex,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onSort!(column),
            child: content,
          ),
        ),
      );
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFD),
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(children: [
        SizedBox(
          width: _colCheckbox,
          child: Checkbox(
            value: allSelected,
            activeColor: AppColors.actionBlue,
            onChanged: onToggleAll == null
                ? null
                : (v) => onToggleAll!(v ?? false),
          ),
        ),
        sortable('APPLICANT', 'surname', flex: 3),
        if (!hidden.contains('municipality'))
          h('MUNICIPALITY', flex: 2),
        if (!hiredOnly) ...[
          if (!hidden.contains('position')) h('POSITION APPLIED', flex: 2),
          if (!hidden.contains('office')) h('OFFICE', flex: 3),
        ],
        if (!hiredOnly && !hidden.contains('dateApplied'))
          h('DATE APPLIED', flex: 2),
        if (!hidden.contains('status'))
          h('STATUS', flex: 2),
        if (hiredOnly) ...[
          if (!hidden.contains('dateHired')) h('DATE HIRED', flex: 2),
          if (!hidden.contains('finalPosition')) h('FINAL POSITION', flex: 2),
          if (!hidden.contains('finalDepartment'))
            h('FINAL DEPARTMENT', flex: 3),
        ],
        h('ACTION', flex: 2),
      ]),
    );
  }
}

class _BrowseRowTile extends StatelessWidget {
  const _BrowseRowTile({
    required this.row,
    required this.hiredOnly,
    required this.dateFormat,
    required this.striped,
    this.hidden = const {},
    this.onHire,
    this.onUnhire,
    this.onReject,
    this.isFlashing = false,
    this.selected = false,
    this.onToggleSelected,
  });

  final BrowseRow row;
  final bool hiredOnly;
  final DateFormat dateFormat;
  final bool striped;
  final Set<String> hidden;
  final ValueChanged<BrowseRow>? onHire;
  final ValueChanged<BrowseRow>? onUnhire;
  final ValueChanged<BrowseRow>? onReject;
  final bool isFlashing;
  final bool selected;
  final void Function(int id, bool selected)? onToggleSelected;

  @override
  Widget build(BuildContext context) {
    String date(DateTime? d) => d == null ? '—' : dateFormat.format(d);

    Widget cell(String? text, {int flex = 1, FontWeight? weight}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              (text ?? '').trim().isEmpty ? '—' : text!,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(fontWeight: weight),
            ),
          ),
        );

    Widget pillCell(String? status, {int flex = 1}) {
      final text = (status ?? '').trim();
      if (text.isEmpty) return cell('—', flex: flex);
      final pal = statusPaletteFor(text);
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: pal.background, borderRadius: AppRadius.pillAll),
              child: Text(text,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.chip.copyWith(color: pal.ink)),
            ),
          ),
        ),
      );
    }

    final name = row.applicant.trim();
    final course = (row.course ?? '').trim();

    final applicantCell = Expanded(
      flex: 3,
      child: Row(
        children: [
          InitialAvatar(name: name),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? '—' : name,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
                if (course.isNotEmpty)
                  Text(course,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );

    return InkWell(
      onTap: () => context.go('/master-data?id=${row.masterdataId}'),
      hoverColor: const Color(0xFFF8F9FC),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isFlashing
              ? const Color(0x22E74C5E) // brief red flash
              : (row.status == 'Rejected'
                  ? const Color(0x08E74C5E) // subtle red tint for rejected
                  : (striped ? AppColors.surface2 : AppColors.surface)),
          border: const Border(
              bottom: BorderSide(color: Color(0xFFF5F6FA))),
        ),
        child: Row(children: [
          SizedBox(
            width: _ResultsGrid._colCheckbox,
            child: row.id == null
                ? null
                : Checkbox(
                    value: selected,
                    activeColor: AppColors.actionBlue,
                    onChanged: onToggleSelected == null
                        ? null
                        : (v) => onToggleSelected!(row.id!, v ?? false),
                  ),
          ),
          applicantCell,
          if (!hidden.contains('municipality'))
            cell(row.municipality, flex: 2),
          if (!hiredOnly) ...[
            if (!hidden.contains('position'))
              cell(row.position, flex: 2),
            if (!hidden.contains('office'))
              cell(row.department, flex: 3),
          ],
          if (!hiredOnly && !hidden.contains('dateApplied'))
            cell(date(row.appDate), flex: 2),
          if (!hidden.contains('status'))
            pillCell(row.status, flex: 2),
          if (hiredOnly) ...[
            if (!hidden.contains('dateHired'))
              cell(date(row.hiredDate), flex: 2),
            if (!hidden.contains('finalPosition'))
              cell(row.finalPosition, flex: 2),
            if (!hidden.contains('finalDepartment'))
              cell(row.finalDepartment, flex: 3),
          ],
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: hiredOnly
                  ? OutlinedButton(
                      style: AppButtonStyles.compact,
                      onPressed: onUnhire == null ? null : () => onUnhire!(row),
                      child: const Text('Unhire'),
                    )
                  : row.status == 'Rejected'
                      ? Text(
                          'Rejected',
                          style: AppTypography.chip.copyWith(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton(
                              style: AppButtonStyles.success,
                              onPressed: onHire == null ? null : () => onHire!(row),
                              child: const Text('Hire'),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton(
                              style: AppButtonStyles.danger,
                              onPressed: onReject == null ? null : () => onReject!(row),
                              child: const Text('Reject'),
                            ),
                          ],
                        ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Bucket a status string the same way [statusPaletteFor] colors it, so the
/// List tab's Pending/Rejected stat cards can never disagree with how a row's
/// own pill is colored.
String _statusBucket(String label) {
  final probe = label.toLowerCase();
  if (probe.contains('hire')) return 'hired';
  if (probe.contains('reject')) return 'rejected';
  if (probe.contains('interview') ||
      probe.contains('pending') ||
      probe.contains('process') ||
      probe.contains('review')) {
    return 'pending';
  }
  return 'other';
}

/// Stat cards at the top of the List/Hired screens — global KPIs (same
/// figures regardless of the page's own search/filter state), reusing the
/// existing dashboard summary endpoint rather than a bespoke aggregation.
class _StatsRow extends ConsumerWidget {
  const _StatsRow({required this.hiredOnly});
  final bool hiredOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(dashboardSummaryProvider('all'));

    if (hiredOnly) {
      final month = ref.watch(dashboardSummaryProvider('month'));
      return Row(children: [
        Expanded(
          child: _StatCard(
            icon: const Icon(Icons.check_circle_outline, size: 17, color: AppColors.okInk),
            iconBack: AppColors.okBack,
            label: 'Total Hired',
            value: all.maybeWhen(data: (s) => '${s.hiredThisYear}', orElse: () => '—'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(
            icon: const Icon(Icons.calendar_month_outlined, size: 17, color: AppColors.infoInk),
            iconBack: AppColors.infoBack,
            label: 'This Month',
            value: month.maybeWhen(data: (s) => '${s.hiredThisYear}', orElse: () => '—'),
          ),
        ),
      ]);
    }

    int bucket(String key) => all.maybeWhen(
          data: (s) => s.statusBreakdown
              .where((l) => _statusBucket(l.label) == key)
              .fold<int>(0, (sum, l) => sum + l.count),
          orElse: () => 0,
        );

    return Row(children: [
      Expanded(
        child: _StatCard(
          icon: const Text('👤', style: TextStyle(fontSize: 15)),
          iconBack: AppColors.infoBack,
          label: 'Total',
          value: all.maybeWhen(data: (s) => '${s.applicantsOnFile}', orElse: () => '—'),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: _StatCard(
          icon: const Text('📋', style: TextStyle(fontSize: 15)),
          iconBack: AppColors.warnBack,
          label: 'Pending',
          value: all.maybeWhen(data: (_) => '${bucket('pending')}', orElse: () => '—'),
        ),
      ),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconBack,
    required this.label,
    required this.value,
  });
  final Widget icon;
  final Color iconBack;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: iconBack, borderRadius: BorderRadius.circular(7)),
            child: icon,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Appears above the table only while rows are checked — applies one status
/// to every selected application via the existing bulk-status endpoint.
/// Numbered pagination (Prev, 1 2 3 … N, Next) — page size stays fixed at
/// [browsePageSize]; this only changes how page navigation is presented.
class _Pager extends StatelessWidget {
  const _Pager({required this.currentPage, required this.total, required this.onGoTo});
  final int currentPage;
  final int total;
  final ValueChanged<int> onGoTo;

  @override
  Widget build(BuildContext context) {
    final pageCount = total == 0 ? 1 : (total / browsePageSize).ceil();

    Widget pageButton(int p, {IconData? icon, bool disabled = false}) {
      final active = !disabled && icon == null && p == currentPage;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          width: 30,
          height: 30,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: active ? AppColors.actionBlue : AppColors.surface,
              foregroundColor: active ? Colors.white : AppColors.ink,
              side: BorderSide(color: active ? AppColors.actionBlue : AppColors.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ).copyWith(
              elevation: const WidgetStatePropertyAll(0),
            ),
            onPressed: disabled ? null : () => onGoTo(p),
            child: icon != null ? Icon(icon, size: 15) : Text('${p + 1}'),
          ),
        ),
      );
    }

    // Up to 7 numbered buttons shown directly; beyond that, collapse the
    // middle behind an ellipsis (first 3 … last 3, keeping current page
    // visible), matching the spec's "1,2,3,…,9" pattern.
    List<int> visiblePages() {
      if (pageCount <= 7) return List.generate(pageCount, (i) => i);
      final set = <int>{0, 1, 2, pageCount - 3, pageCount - 2, pageCount - 1,
          currentPage - 1, currentPage, currentPage + 1};
      return set.where((p) => p >= 0 && p < pageCount).toList()..sort();
    }

    final pages = visiblePages();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          pageButton(currentPage - 1, icon: Icons.chevron_left, disabled: currentPage == 0),
          for (var i = 0; i < pages.length; i++) ...[
            if (i > 0 && pages[i] - pages[i - 1] > 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Text('…', style: AppTypography.caption),
              ),
            pageButton(pages[i]),
          ],
          pageButton(currentPage + 1,
              icon: Icons.chevron_right, disabled: currentPage >= pageCount - 1),
        ],
      ),
    );
  }
}

/// Result returned by the unhire dialog.
class _UnhireResult {
  const _UnhireResult({this.status});
  final String? status;
}

/// Confirmation dialog for unhiring — shows applicant info and lets the user
/// pick a status to set when the applicant returns to the list.
class _UnhireDialog extends StatefulWidget {
  const _UnhireDialog({required this.row});
  final BrowseRow row;

  @override
  State<_UnhireDialog> createState() => _UnhireDialogState();
}

class _UnhireDialogState extends State<_UnhireDialog> {
  String? _selectedStatus;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final fmt = DateFormat('MMM dd, yyyy');

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.warnBack,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.unarchive_outlined,
                color: AppColors.warnInk, size: 20),
          ),
          const SizedBox(width: 10),
          const Text('Unhire applicant'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Applicant info card
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  InitialAvatar(name: row.applicant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.applicant,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        if (row.finalPosition != null)
                          Text('Final position: ${row.finalPosition}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.muted)),
                        if (row.hiredDate != null)
                          Text('Date hired: ${fmt.format(row.hiredDate!)}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'This applicant will move back to List of Applicants. '
              'Final position and date hired will be cleared.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            // Status dropdown
            Labeled(
              label: 'Set status',
              child: SizedBox(
                height: 36,
                child: SearchableDropdown(
                  options: const [
                    'On Process',
                    'For Interview',
                    'Recommended',
                    'Evaluated',
                    'Initial Screening',
                  ],
                  value: _selectedStatus,
                  hint: 'Choose status (optional)',
                  allowClear: true,
                  onChanged: (v) => setState(() => _selectedStatus = v),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.warnInk,
          ),
          onPressed: () => Navigator.pop(
              context, _UnhireResult(status: _selectedStatus)),
          child: const Text('Unhire'),
        ),
      ],
    );
  }
}
