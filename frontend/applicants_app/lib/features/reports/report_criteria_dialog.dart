import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../lookups/lookups_provider.dart';
import '../master_data/widgets/form_bits.dart';

class ReportCriteria {
  ReportCriteria({
    required this.title,
    this.sortMode = 'original',
    this.dateFrom,
    this.dateTo,
    this.recommendation,
    this.position,
    this.department,
    this.education,
    this.status,
    this.hiredFrom,
    this.hiredTo,
  });

  String title;
  String sortMode;
  DateTime? dateFrom;
  DateTime? dateTo;
  String? recommendation;
  String? position;
  String? department;
  String? education;
  String? status;
  DateTime? hiredFrom;
  DateTime? hiredTo;

  Map<String, dynamic> toJson() => {
        'title': title,
        'sortMode': sortMode,
        'dateFrom': dateFrom?.toIso8601String(),
        'dateTo': dateTo?.toIso8601String(),
        'recommendation': recommendation,
        'position': position,
        'department': department,
        'education': education,
        'status': status,
        'hiredFrom': hiredFrom?.toIso8601String(),
        'hiredTo': hiredTo?.toIso8601String(),
      };
}

/// Criteria step before generating the List/Hired PDF — replaces the old
/// reportform/hiredreportform criteria grids. Blank fields mean "all";
/// text fields accept slash-separated alternatives ("Nurse/Midwife").
Future<ReportCriteria?> showReportCriteriaDialog(
  BuildContext context, {
  required bool hired,
  required Lookups lookups,
  List<String> statusSuggestions = const [],
}) {
  return showDialog<ReportCriteria>(
    context: context,
    builder: (context) => _CriteriaDialog(
      hired: hired,
      lookups: lookups,
      statusSuggestions: statusSuggestions,
    ),
  );
}

class _CriteriaDialog extends StatefulWidget {
  const _CriteriaDialog({
    required this.hired,
    required this.lookups,
    this.statusSuggestions = const [],
  });
  final bool hired;
  final Lookups lookups;
  final List<String> statusSuggestions;

  @override
  State<_CriteriaDialog> createState() => _CriteriaDialogState();
}

class _CriteriaDialogState extends State<_CriteriaDialog> {
  late final criteria = ReportCriteria(
    title: widget.hired
        ? 'Monthly Employment Report'
        : 'Report on Status of Application',
  );
  late final _title = TextEditingController(text: criteria.title);
  final _recommendation = TextEditingController();
  final _position = TextEditingController();
  final _department = TextEditingController();
  final _education = TextEditingController();
  final _status = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _recommendation.dispose();
    _position.dispose();
    _department.dispose();
    _education.dispose();
    _status.dispose();
    super.dispose();
  }

  Widget _rangeField(String label, DateTime? from, DateTime? to,
      void Function(DateTime?, DateTime?) set) {
    final fmt = DateFormat('MMM dd, yyyy');
    return Labeled(
      label: label,
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              side: const BorderSide(color: AppColors.comboBorder),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
            onPressed: () async {
              final now = DateTime.now();
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2005),
                lastDate: DateTime(now.year + 1, 12, 31),
                initialDateRange: from == null
                    ? null
                    : DateTimeRange(start: from, end: to ?? now),
              );
              if (range != null) setState(() => set(range.start, range.end));
            },
            child: Text(
              from == null
                  ? 'All dates'
                  : '${fmt.format(from)} – ${to == null ? '…' : fmt.format(to)}',
              style: AppTypography.body.copyWith(
                  color: from == null ? AppColors.muted : AppColors.ink),
            ),
          ),
        ),
        if (from != null)
          IconButton(
            icon: const Icon(Icons.close, size: 14, color: AppColors.muted),
            tooltip: 'Clear',
            onPressed: () => setState(() => set(null, null)),
          ),
      ]),
    );
  }

  Widget _textField(String label, TextEditingController controller,
      {String? hint}) {
    return Labeled(
      label: label,
      child: TextField(
        controller: controller,
        style: kValueStyle,
        decoration: kInputDecoration.copyWith(hintText: hint ?? 'All'),
      ),
    );
  }

  /// Same free-text-with-suggestions field used for status elsewhere in the
  /// app (see [AutocompleteTextField]) — picking a suggestion or typing
  /// anything at all both work, so slash-separated alternatives still work.
  Widget _autocompleteField(String label, TextEditingController controller,
      List<String> suggestions, {String? hint}) {
    return Labeled(
      label: label,
      child: AutocompleteTextField(
        controller: controller,
        suggestions: suggestions,
        hint: hint ?? 'All',
        onChanged: (_) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.hired
          ? 'Print report — Hired Applicants'
          : 'Print report — List of Applicants'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _textField('Report title', _title),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _rangeField(
                        'Application date range', criteria.dateFrom,
                        criteria.dateTo, (a, b) {
                  criteria.dateFrom = a;
                  criteria.dateTo = b;
                })),
                if (widget.hired) ...[
                  const SizedBox(width: 12),
                  Expanded(
                      child: _rangeField(
                          'Hiring date range', criteria.hiredFrom,
                          criteria.hiredTo, (a, b) {
                    criteria.hiredFrom = a;
                    criteria.hiredTo = b;
                  })),
                ],
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _autocompleteField(
                        'Recommendation',
                        _recommendation,
                        widget.lookups.officers
                            .map((o) => o.recommending)
                            .toList(),
                        hint: 'All — use / for alternatives')),
                const SizedBox(width: 12),
                Expanded(
                    child: _textField('Position', _position,
                        hint: 'All — e.g. Nurse/Midwife')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _autocompleteField('Department / office',
                        _department, widget.lookups.departments)),
                const SizedBox(width: 12),
                Expanded(
                    child: _autocompleteField('Education / course', _education,
                        widget.lookups.education)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _autocompleteField(
                        widget.hired ? 'Final status' : 'Application status',
                        _status,
                        widget.statusSuggestions)),
                const SizedBox(width: 12),
                Expanded(
                  child: Labeled(
                    label: 'Arrangement',
                    child: SearchableDropdown(
                      options: const [
                        'Alphabetical (original)',
                        'Group by recommending officer',
                        'Group by educational attainment',
                      ],
                      value: switch (criteria.sortMode) {
                        'recommendation' => 'Group by recommending officer',
                        'education' => 'Group by educational attainment',
                        _ => 'Alphabetical (original)',
                      },
                      allowClear: false,
                      onChanged: (v) => criteria.sortMode = switch (v) {
                        'Group by recommending officer' => 'recommendation',
                        'Group by educational attainment' => 'education',
                        _ => 'original',
                      },
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: const Text('Generate PDF'),
          onPressed: () {
            criteria.title = _title.text.trim();
            String? clean(TextEditingController c) =>
                c.text.trim().isEmpty ? null : c.text.trim();
            criteria.recommendation = clean(_recommendation);
            criteria.position = clean(_position);
            criteria.department = clean(_department);
            criteria.education = clean(_education);
            criteria.status = clean(_status);
            Navigator.of(context).pop(criteria);
          },
        ),
      ],
    );
  }
}
