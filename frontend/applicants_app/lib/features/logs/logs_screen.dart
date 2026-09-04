import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/status_color.dart';
import '../../shared/widgets/page_header.dart';
import '../master_data/widgets/form_bits.dart';
import 'logs_provider.dart';

/// Per-entry Action-column label + color — a specific, readable label for
/// every real action (not the dropdown's coarser bucket grouping), so the
/// timeline still reads precisely even for the "Other"-bucket actions.
({String label, Color back, Color ink}) _actionBadge(AuditEntry e) {
  switch ('${e.entityType}.${e.action}') {
    case 'application.hire':
      return (label: 'Hired', back: AppColors.okBack, ink: AppColors.okInk);
    case 'application.bulk-status':
      return (label: 'Status Change', back: AppColors.okBack, ink: AppColors.okInk);
    case 'masterdata.insert':
      return (label: 'Applicant Added', back: AppColors.infoBack, ink: AppColors.infoInk);
    case 'masterdata.update':
      return (label: 'Applicant Edited', back: AppColors.violetBack, ink: AppColors.violetInk);
    case 'report.generate':
    case 'report.save_copy':
      return (label: 'Report Generated', back: AppColors.warnBack, ink: AppColors.warnInk);
    case 'auth.login':
      return (label: 'Login', back: AppColors.dangerBack, ink: AppColors.dangerInk);
    case 'auth.logout':
      return (label: 'Logout', back: AppColors.neutralBack, ink: AppColors.neutralInk);
    case 'auth.login_failed':
      return (label: 'Failed Login', back: AppColors.neutralBack, ink: AppColors.neutralInk);
    case 'auth.change_password':
      return (label: 'Password Changed', back: AppColors.neutralBack, ink: AppColors.neutralInk);
    case 'auth.update_profile':
      return (label: 'Profile Updated', back: AppColors.neutralBack, ink: AppColors.neutralInk);
    case 'masterdata.archive':
      return (label: 'Archived', back: AppColors.neutralBack, ink: AppColors.neutralInk);
    case 'masterdata.restore':
      return (label: 'Restored', back: AppColors.neutralBack, ink: AppColors.neutralInk);
    case 'masterdata.import':
      return (label: 'Imported', back: AppColors.neutralBack, ink: AppColors.neutralInk);
    case 'status.merge':
      return (label: 'Status Merged', back: AppColors.neutralBack, ink: AppColors.neutralInk);
    case 'lookup.quick_add':
      return (label: 'Lookup Added', back: AppColors.neutralBack, ink: AppColors.neutralInk);
    case 'lookup.batch_save':
      return (label: 'Parameters Edited', back: AppColors.neutralBack, ink: AppColors.neutralInk);
    case 'application.unhire':
      return (label: 'Unhired', back: AppColors.neutralBack, ink: AppColors.neutralInk);
    default:
      return (label: e.action, back: AppColors.neutralBack, ink: AppColors.neutralInk);
  }
}

/// Details-column text — like AuditEntry.summary but without the leading
/// "$who" (the User column already shows that), and with the applicant
/// status value (when the detail is a bulk-status change) pulled out to
/// render as its own small inline pill instead of raw text.
class _DetailsContent extends StatelessWidget {
  const _DetailsContent({required this.entry});
  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final detail = entry.detail;
    if (entry.entityType == 'application' &&
        entry.action == 'bulk-status' &&
        detail != null &&
        detail.startsWith('status -> ')) {
      final status = detail.substring('status -> '.length);
      final pal = statusPaletteFor(status);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Status changed to ', style: TextStyle(fontSize: 12, color: AppColors.ink)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: pal.background, borderRadius: BorderRadius.circular(4)),
            child: Text(status,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: pal.ink)),
          ),
        ],
      );
    }
    return Text(detail == null || detail.isEmpty ? '—' : detail,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: AppColors.ink));
  }
}

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(logsFiltersProvider).search;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _applyDebounced(LogsFilters Function(LogsFilters) change) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(logsFiltersProvider.notifier).update(change(ref.read(logsFiltersProvider)));
    });
  }

  void _applyNow(LogsFilters Function(LogsFilters) change) {
    ref.read(logsFiltersProvider.notifier).update(change(ref.read(logsFiltersProvider)));
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(logsFiltersProvider);
    final results = ref.watch(logsResultsProvider);
    final fmt = DateFormat('MMM d, yyyy h:mm a');

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(title: 'Activity Logs'),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 220,
                height: 36,
                child: TextField(
                  controller: _search,
                  style: kValueStyle.copyWith(fontSize: 13),
                  decoration: kInputDecoration.copyWith(
                    hintText: 'Search logs…',
                    prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.muted),
                  ),
                  onChanged: (v) => _applyDebounced((f) => f.copyWith(search: v)),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 170,
                height: 36,
                child: SearchableDropdown(
                  options: kLogBuckets.values.toList(),
                  value: filters.bucket == null ? null : kLogBuckets[filters.bucket],
                  hint: 'All Actions',
                  onChanged: (label) => _applyNow((f) => label == null
                      ? f.copyWith(clearBucket: true)
                      : f.copyWith(
                          bucket: kLogBuckets.entries
                              .firstWhere((e) => e.value == label)
                              .key)),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 170,
                height: 36,
                child: Consumer(
                  builder: (context, ref, _) {
                    final users = ref.watch(logUsersProvider);
                    return users.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (names) => SearchableDropdown(
                        options: [for (final u in names) displayNameFor(u)],
                        value: filters.changedBy == null ? null : displayNameFor(filters.changedBy),
                        hint: 'All Users',
                        onChanged: (display) => _applyNow((f) {
                          if (display == null) return f.copyWith(clearChangedBy: true);
                          final username = names.firstWhere(
                              (u) => displayNameFor(u) == display,
                              orElse: () => display);
                          return f.copyWith(changedBy: username);
                        }),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Could not load logs: $e', style: AppTypography.helper),
              ),
              data: (page) => page.rows.isEmpty
                  ? const Center(child: Text('No activity recorded yet.', style: AppTypography.helper))
                  : Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(color: AppColors.line),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFAFBFD),
                              border: Border(bottom: BorderSide(color: AppColors.line)),
                            ),
                            child: const Row(children: [
                              SizedBox(
                                  width: 160,
                                  child: Text('TIMESTAMP', style: AppTypography.tableHeader)),
                              Expanded(
                                  flex: 2,
                                  child: Text('USER', style: AppTypography.tableHeader)),
                              Expanded(
                                  flex: 2,
                                  child: Text('ACTION', style: AppTypography.tableHeader)),
                              Expanded(
                                  flex: 4,
                                  child: Text('DETAILS', style: AppTypography.tableHeader)),
                            ]),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: page.rows.length,
                              itemBuilder: (context, i) {
                                final e = page.rows[i];
                                final badge = _actionBadge(e);
                                return Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Color(0xFFE4E7EF))),
                                  ),
                                  child: Row(children: [
                                    SizedBox(
                                      width: 160,
                                      child: Text(
                                        fmt.format(e.changedAt.toLocal()),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.muted,
                                            fontFamily: 'monospace'),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        displayNameFor(e.changedBy),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.ink),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                              color: badge.back,
                                              borderRadius: BorderRadius.circular(10)),
                                          child: Text(badge.label,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: badge.ink)),
                                        ),
                                      ),
                                    ),
                                    Expanded(flex: 4, child: _DetailsContent(entry: e)),
                                  ]),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          results.maybeWhen(
            data: (page) => _LogsPagerRow(
              currentPage: filters.page,
              total: page.total,
              pageRowCount: page.rows.length,
              onGoTo: (p) => _applyNow((f) => f.copyWith(page: p)),
            ),
            orElse: () => const SizedBox(height: 30),
          ),
        ],
      ),
    );
  }
}

/// "Showing X–Y of Z entries" on the left, numbered pager on the right —
/// deliberately not centered like the Browse screens' pager, per this
/// screen's own spec.
class _LogsPagerRow extends StatelessWidget {
  const _LogsPagerRow({
    required this.currentPage,
    required this.total,
    required this.pageRowCount,
    required this.onGoTo,
  });
  final int currentPage;
  final int total;
  final int pageRowCount;
  final ValueChanged<int> onGoTo;

  @override
  Widget build(BuildContext context) {
    final start = total == 0 ? 0 : currentPage * logsPageSize + 1;
    final end = currentPage * logsPageSize + pageRowCount;
    final n = NumberFormat('#,##0');

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          total == 0
              ? 'No entries'
              : 'Showing ${n.format(start)}–${n.format(end)} of ${n.format(total)} entries',
          style: AppTypography.caption,
        ),
        _LogsPager(currentPage: currentPage, total: total, onGoTo: onGoTo),
      ],
    );
  }
}

class _LogsPager extends StatelessWidget {
  const _LogsPager({required this.currentPage, required this.total, required this.onGoTo});
  final int currentPage;
  final int total;
  final ValueChanged<int> onGoTo;

  @override
  Widget build(BuildContext context) {
    final pageCount = total == 0 ? 1 : (total / logsPageSize).ceil();

    Widget pageButton(int p, {IconData? icon, bool disabled = false}) {
      final active = !disabled && icon == null && p == currentPage;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Opacity(
            opacity: disabled ? 0.3 : 1,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: active ? AppColors.actionBlue : AppColors.surface,
                foregroundColor: active ? Colors.white : AppColors.ink,
                side: BorderSide(color: active ? AppColors.actionBlue : AppColors.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              ).copyWith(elevation: const WidgetStatePropertyAll(0)),
              onPressed: disabled ? null : () => onGoTo(p),
              child: icon != null ? Icon(icon, size: 15) : Text('${p + 1}'),
            ),
          ),
        ),
      );
    }

    List<int> visiblePages() {
      if (pageCount <= 7) return List.generate(pageCount, (i) => i);
      final set = <int>{
        0, 1, 2, pageCount - 3, pageCount - 2, pageCount - 1,
        currentPage - 1, currentPage, currentPage + 1,
      };
      return set.where((p) => p >= 0 && p < pageCount).toList()..sort();
    }

    final pages = visiblePages();

    return Row(
      mainAxisSize: MainAxisSize.min,
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
    );
  }
}
