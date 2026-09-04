import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/page_header.dart';
import '../lookups/lookups_provider.dart';
import '../master_data/widgets/form_bits.dart';
import '../shell/toast_provider.dart';
import 'report_preview.dart';
import 'reports_provider.dart';

/// Summary Reports tab — per-officer requested-vs-hired counts, straight to
/// PDF (no preview step), like the old recommendreport.cs.
class SummaryReportsScreen extends ConsumerStatefulWidget {
  const SummaryReportsScreen({super.key});

  @override
  ConsumerState<SummaryReportsScreen> createState() =>
      _SummaryReportsScreenState();
}

class _SummaryReportsScreenState extends ConsumerState<SummaryReportsScreen> {
  final Set<String> _ticked = {};

  static final _years = [
    for (var y = 2007; y <= DateTime.now().year + 1; y++) y,
  ];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late int _yearFrom = DateTime.now().year;
  late int _monthFrom = 1;
  late int _yearTo = DateTime.now().year;
  late int _monthTo = DateTime.now().month;
  bool _generating = false;

  bool get _rangeInvalid =>
      _yearFrom > _yearTo || (_yearFrom == _yearTo && _monthFrom > _monthTo);

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final bytes = await ref.read(reportRunnerProvider).fetchPdf(
        '/api/reports/recommendation-summary',
        body: {
          'officers': _ticked.toList(),
          'yearFrom': _yearFrom,
          'monthFrom': _monthFrom,
          'yearTo': _yearTo,
          'monthTo': _monthTo,
        },
      );
      if (mounted) {
        await showReportPreview(context, ref,
            bytes: bytes, suggestedFileName: 'recommendation-summary.pdf');
      }
    } catch (_) {
      if (mounted) {
        ref
            .read(toastProvider.notifier)
            .show('Unable to produce the report — is the service running?');
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lookups = ref.watch(lookupsProvider);

    return lookups.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Could not load officers: $e', style: AppTypography.helper)),
      data: (data) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(title: 'Summary by Recommendation'),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- officer checklist ----
                  Expanded(
                    child: SectionCard(
                      title: 'Recommending officers',
                      child: SizedBox(
                        height: 420,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              OutlinedButton(
                                onPressed: _ticked.isEmpty
                                    ? null
                                    : () => setState(_ticked.clear),
                                child: const Text('Untick all'),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _ticked.isEmpty
                                      ? 'No officers ticked — the summary includes everyone.'
                                      : '${_ticked.length} officer(s) ticked — the summary is limited to them.',
                                  style: AppTypography.helper,
                                ),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.builder(
                                itemCount: data.officers.length,
                                itemExtent: 48,
                                itemBuilder: (context, i) {
                                  final o = data.officers[i];
                                  final ticked = _ticked.contains(o.recommending);
                                  return CheckboxListTile(
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    value: ticked,
                                    title: Text(o.recommending, style: AppTypography.body),
                                    subtitle: null,
                                    onChanged: (v) => setState(() {
                                      if (v ?? false) {
                                        _ticked.add(o.recommending);
                                      } else {
                                        _ticked.remove(o.recommending);
                                      }
                                    }),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // ---- parameters ----
                  SizedBox(
                    width: 460,
                    child: SectionCard(
                      title: 'Report parameters',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PERIOD', style: AppTypography.fieldLabel),
                          const SizedBox(height: 6),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Semantics(
                                label: 'Start year',
                                child: SizedBox(
                                  width: 108,
                                  height: 36,
                                  child: SearchableDropdown(
                                    options: [for (final y in _years) '$y'],
                                    value: '$_yearFrom',
                                    allowClear: false,
                                    onChanged: (v) => setState(() =>
                                        _yearFrom = int.tryParse(v ?? '') ?? _yearFrom),
                                  ),
                                ),
                              ),
                              Semantics(
                                label: 'Start month',
                                child: SizedBox(
                                  width: 130,
                                  height: 36,
                                  child: SearchableDropdown(
                                    options: _months,
                                    value: _months[_monthFrom - 1],
                                    allowClear: false,
                                    onChanged: (v) => setState(() => _monthFrom =
                                        v == null ? _monthFrom : _months.indexOf(v) + 1),
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2),
                                child: Text('to', style: AppTypography.helper),
                              ),
                              Semantics(
                                label: 'End year',
                                child: SizedBox(
                                  width: 108,
                                  height: 36,
                                  child: SearchableDropdown(
                                    options: [for (final y in _years) '$y'],
                                    value: '$_yearTo',
                                    allowClear: false,
                                    onChanged: (v) => setState(() =>
                                        _yearTo = int.tryParse(v ?? '') ?? _yearTo),
                                  ),
                                ),
                              ),
                              Semantics(
                                label: 'End month',
                                child: SizedBox(
                                  width: 130,
                                  height: 36,
                                  child: SearchableDropdown(
                                    options: _months,
                                    value: _months[_monthTo - 1],
                                    allowClear: false,
                                    onChanged: (v) => setState(() => _monthTo =
                                        v == null ? _monthTo : _months.indexOf(v) + 1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Semantics(
                            label: 'Generate report',
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                              label: Text(_generating ? 'Generating…' : 'Generate'),
                              onPressed:
                                  (_generating || _rangeInvalid) ? null : _generate,
                            ),
                          ),
                          if (_rangeInvalid)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                  'The start of the period must not be after the end.',
                                  style: AppTypography.helper
                                      .copyWith(color: AppColors.danger)),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            'Tick officers to limit the summary to specific '
                            'recommenders — leave all unticked to include everyone. '
                            'The period is inclusive. Opens as a PDF.',
                            style: AppTypography.helper.copyWith(height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
