import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_button_styles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/master_data.dart';
import '../../shared/widgets/page_header.dart';
import '../auth/auth_provider.dart';
import '../shell/toast_provider.dart';
import 'widgets/form_bits.dart';

final _archivedSearchProvider =
    NotifierProvider<_ArchivedSearchNotifier, String>(
        _ArchivedSearchNotifier.new);

class _ArchivedSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}

// autoDispose: refetch every time the screen opens, so someone archived a
// moment ago in Master Data shows up immediately.
final _archivedListProvider =
    FutureProvider.autoDispose<List<SearchRow>>((ref) async {
  final search = ref.watch(_archivedSearchProvider);
  final api = ref.read(apiClientProvider);
  final q = search.trim().isEmpty
      ? ''
      : '?search=${Uri.encodeComponent(search.trim())}';
  final json = await api.get('/api/masterdata/archived$q') as List;
  return json.map((e) => SearchRow.fromJson(e as Map<String, dynamic>)).toList();
});

/// Archived applicants — the recovery view the old app never had. Restoring
/// flips archived=0 and the record reappears everywhere.
class ArchivedScreen extends ConsumerStatefulWidget {
  const ArchivedScreen({super.key});

  @override
  ConsumerState<ArchivedScreen> createState() => _ArchivedScreenState();
}

class _ArchivedScreenState extends ConsumerState<ArchivedScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _restore(SearchRow row) async {
    final ok = await confirmDialog(
      context,
      title: 'Restore this applicant?',
      message:
          '${row.displayName} will reappear in Master Data, the applicant lists, '
          'the dashboard, and reports.',
      confirmLabel: 'Restore',
    );
    if (!ok) return;
    try {
      await ref
          .read(apiClientProvider)
          .post('/api/masterdata/${row.id}/restore');
      ref.invalidate(_archivedListProvider);
      if (mounted) {
        ref.read(toastProvider.notifier).show('Applicant restored');
      }
    } catch (_) {
      if (mounted) {
        ref.read(toastProvider.notifier).show('Restore failed');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_archivedListProvider);
    final fmt = DateFormat('MMM dd, yyyy');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: PageHeader(
            title: 'Archived Applicants',
            parentTitle: 'Master Data',
            onParentTap: () => context.go('/master-data'),
            subtitle: 'Hidden from every list and report, but never deleted.',
            actions: [
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back, size: 15),
                label: const Text('Back to Master Data'),
                onPressed: () => context.go('/master-data'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, AppSpacing.md, 18, 0),
          child: SizedBox(
            width: 320,
            height: 40,
            child: TextField(
              controller: _search,
              style: AppTypography.body,
              decoration: kInputDecoration.copyWith(
                hintText: 'Search archived by name…',
                prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.muted),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  ref.read(_archivedSearchProvider.notifier).set(v);
                });
              },
            ),
          ),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Could not load archived applicants: $e',
                  style: AppTypography.helper),
            ),
            data: (rows) => rows.isEmpty
                ? const Center(
                    child: Text('No archived applicants.', style: AppTypography.helper),
                  )
                : Container(
                    margin: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(color: AppColors.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemExtent: 62,
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        return Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: i.isOdd
                                ? AppColors.surface2
                                : AppColors.surface,
                            border: const Border(
                                bottom: BorderSide(
                                    color: AppColors.line, width: .5)),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 240,
                                child: Text(row.displayName,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodyStrong),
                              ),
                              SizedBox(
                                width: 160,
                                child: Text(row.municipality ?? '—',
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.helper),
                              ),
                              Expanded(
                                child: Text(
                                  row.dbirth == null
                                      ? ''
                                      : 'b. ${fmt.format(row.dbirth!)}',
                                  style: AppTypography.helper,
                                ),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.restore, size: 14),
                                label: const Text('Restore'),
                                style: AppButtonStyles.compact,
                                onPressed: () => _restore(row),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
