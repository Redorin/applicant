import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/status_color.dart';
import '../auth/auth_provider.dart';
import '../dashboard/dashboard_provider.dart';
import '../master_data/widgets/form_bits.dart';
import '../shell/toast_provider.dart';
import 'statuses_provider.dart';

/// Lists every status spelling in use and lets the user merge a stray
/// variant ("Active Files") into the canonical one ("Active File").
class StatusVariantsCard extends ConsumerWidget {
  const StatusVariantsCard({super.key});

  Future<void> _merge(BuildContext context, WidgetRef ref,
      StatusVariant from, List<StatusVariant> all) async {
    String? target;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge status spelling'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Every application marked '),
                TextSpan(
                    text: '"${from.status}"',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(
                    text:
                        ' (${NumberFormat('#,##0').format(from.total)} rows) will be relabeled as:'),
              ])),
              const SizedBox(height: 12),
              SearchableDropdown(
                options: [
                  for (final v in all)
                    if (v.status != from.status) v.status,
                ],
                hint: 'Pick the correct spelling…',
                allowClear: false,
                onChanged: (v) => target = v,
              ),
              const SizedBox(height: 10),
              const Text(
                'This cannot be undone from the app (a daily database backup '
                'is taken first). The dashboard and reports will count the '
                'merged spelling as one status afterwards.',
                style: AppTypography.helper,
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Merge')),
        ],
      ),
    );

    if (confirmed != true || target == null || target!.trim().isEmpty) return;

    try {
      final res = await ref.read(apiClientProvider).post('/api/statuses/merge',
          body: {'from': from.status, 'to': target});
      final n = (res['updatedStatus'] as int) + (res['updatedFinalStatus'] as int);
      ref.invalidate(statusVariantsProvider);
      ref.invalidate(dashboardProvider);
      ref.read(toastProvider.notifier)
          .show('Relabeled ${NumberFormat('#,##0').format(n)} rows');
    } on ApiException catch (e) {
      ref.read(toastProvider.notifier).show('Merge failed: ${e.message}');
    } catch (_) {
      ref.read(toastProvider.notifier).show('Merge failed');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variants = ref.watch(statusVariantsProvider);
    final n = NumberFormat('#,##0');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status spellings in use', style: AppTypography.bodyStrong),
                SizedBox(height: 2),
                Text(
                  'Free-text statuses accumulate variants over the years '
                  '("Active File" vs "Active Files"). Merge stray spellings so '
                  'counts and reports treat them as one.',
                  style: AppTypography.helper,
                ),
              ],
            ),
          ),
          variants.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not load statuses: $e', style: AppTypography.helper),
            ),
            data: (list) => ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemExtent: 52,
                itemBuilder: (context, i) {
                  final v = list[i];
                  final pal = statusPaletteFor(v.status);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: i.isOdd ? AppColors.surface2 : AppColors.surface,
                      border: const Border(
                          top: BorderSide(color: AppColors.line, width: .5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: pal.background,
                            borderRadius: AppRadius.pillAll,
                          ),
                          child: Text(v.status,
                              style: AppTypography.chip.copyWith(color: pal.ink)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${n.format(v.inStatus)} as status'
                            '${v.inFinalStatus > 0 ? ' · ${n.format(v.inFinalStatus)} as final status' : ''}',
                            style: AppTypography.helper,
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => _merge(context, ref, v, list),
                          child: const Text('Merge into…'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
