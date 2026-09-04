import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/page_header.dart';
import '../auth/auth_provider.dart';
import 'status_variants_card.dart';

class HealthCategory {
  const HealthCategory(this.key, this.title, this.description, this.count);

  factory HealthCategory.fromJson(Map<String, dynamic> json) => HealthCategory(
        json['key'] as String,
        json['title'] as String,
        json['description'] as String,
        json['count'] as int,
      );

  final String key;
  final String title;
  final String description;
  final int count;
}

class HealthRow {
  const HealthRow(this.masterdataId, this.applicant, this.detail);

  factory HealthRow.fromJson(Map<String, dynamic> json) => HealthRow(
        json['masterdataId'] as int,
        (json['applicant'] as String?) ?? '',
        (json['detail'] as String?) ?? '',
      );

  final int masterdataId;
  final String applicant;
  final String detail;
}

final healthSummaryProvider = FutureProvider<List<HealthCategory>>((ref) async {
  final api = ref.read(apiClientProvider);
  final json = await api.get('/api/datahealth/summary') as List;
  return json
      .map((e) => HealthCategory.fromJson(e as Map<String, dynamic>))
      .toList();
});

// autoDispose: unlike the fixed-size lookups/page providers elsewhere, this
// scales with real data-quality issue counts across the full applicant base
// (could be hundreds-to-thousands of rows for a "dirty" category) — once the
// user collapses a category card and stops watching it, there's no reason to
// keep holding that list in memory for the rest of the session.
final healthRowsProvider =
    FutureProvider.autoDispose.family<List<HealthRow>, String>((ref, category) async {
  final api = ref.read(apiClientProvider);
  final json = await api.get('/api/datahealth/$category') as List;
  return json.map((e) => HealthRow.fromJson(e as Map<String, dynamic>)).toList();
});

/// Data Health — turns invisible data rot into a click-to-fix worklist.
class DataHealthScreen extends ConsumerStatefulWidget {
  const DataHealthScreen({super.key});

  @override
  ConsumerState<DataHealthScreen> createState() => _DataHealthScreenState();
}

class _DataHealthScreenState extends ConsumerState<DataHealthScreen> {
  String? _expanded;

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(healthSummaryProvider);

    return summary.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Could not scan the database: $e', style: AppTypography.helper),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => ref.invalidate(healthSummaryProvider),
            child: const Text('Retry'),
          ),
        ]),
      ),
      data: (categories) {
        final clean = categories.every((c) => c.count == 0);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Data Health',
                subtitle: 'Issues found in the live database. Click an item to '
                    'open the record in Master Data, fix it, and save — the '
                    'counts update on the next scan.',
                actions: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('Rescan'),
                    onPressed: () {
                      ref.invalidate(healthSummaryProvider);
                      if (_expanded != null) {
                        ref.invalidate(healthRowsProvider(_expanded!));
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (clean)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.okBack,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: AppColors.okInk, size: 22),
                      const SizedBox(width: 10),
                      Text('No data issues found — everything looks healthy.',
                          style: AppTypography.bodyStrong.copyWith(color: AppColors.okInk)),
                    ],
                  ),
                )
              else
                for (final cat in categories) _categoryCard(cat),
              const SizedBox(height: 6),
              const StatusVariantsCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _categoryCard(HealthCategory cat) {
    final expanded = _expanded == cat.key;
    final hasIssues = cat.count > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: hasIssues
                ? () => setState(() => _expanded = expanded ? null : cat.key)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasIssues ? AppColors.warnBack : AppColors.okBack,
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Text(
                      '${cat.count}',
                      style: AppTypography.chip.copyWith(
                        color: hasIssues ? AppColors.warnInk : AppColors.okInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cat.title, style: AppTypography.bodyStrong),
                        const SizedBox(height: 2),
                        Text(cat.description, style: AppTypography.helper),
                      ],
                    ),
                  ),
                  if (hasIssues)
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.muted,
                    ),
                ],
              ),
            ),
          ),
          if (expanded) _rowsList(cat.key),
        ],
      ),
    );
  }

  Widget _rowsList(String category) {
    final rows = ref.watch(healthRowsProvider(category));
    return rows.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Could not load rows: $e', style: AppTypography.helper),
      ),
      data: (list) => Container(
        constraints: const BoxConstraints(maxHeight: 320),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: list.length,
          itemExtent: 56,
          itemBuilder: (context, i) {
            final row = list[i];
            return InkWell(
              onTap: () => context.go('/master-data?id=${row.masterdataId}'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: i.isOdd ? AppColors.surface2 : AppColors.surface,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: Text(row.applicant,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyStrong.copyWith(fontSize: 14)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(row.detail,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.helper),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 16, color: AppColors.muted),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
