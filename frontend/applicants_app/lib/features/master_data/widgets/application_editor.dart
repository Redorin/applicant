import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../models/master_data.dart';
import '../../../shared/widgets/app_date_picker.dart';
import '../../lookups/lookups_provider.dart';
import 'form_bits.dart';

const empStatusOptions = ['Job Order', 'Casual', 'Consultant', 'Permanent'];

/// Modal editor for one application row (add or edit).
/// Returns the edited row, or null when cancelled.
Future<ApplicationRow?> showApplicationEditor(
  BuildContext context, {
  required Lookups lookups,
  ApplicationRow? existing,
  List<String> statusSuggestions = const [],
}) {
  return showDialog<ApplicationRow>(
    context: context,
    builder: (context) => _ApplicationEditorDialog(
      lookups: lookups,
      existing: existing,
      statusSuggestions: statusSuggestions,
    ),
  );
}

/// Section card with icon, title, and content.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.actionBlue),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: AppTypography.sectionTitle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Section label with icon and hairline underline.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.muted),
        const SizedBox(width: 6),
        Text(text.toUpperCase(), style: AppTypography.sectionTitle),
        const SizedBox(width: 12),
        const Expanded(child: Divider(height: 1)),
      ],
    );
  }
}

class _ApplicationEditorDialog extends StatefulWidget {
  const _ApplicationEditorDialog(
      {required this.lookups, this.existing, this.statusSuggestions = const []});
  final Lookups lookups;
  final ApplicationRow? existing;
  final List<String> statusSuggestions;

  @override
  State<_ApplicationEditorDialog> createState() =>
      _ApplicationEditorDialogState();
}

class _ApplicationEditorDialogState extends State<_ApplicationEditorDialog> {
  late final ApplicationRow row;
  late final TextEditingController _position;
  late final TextEditingController _status;
  late final TextEditingController _finalPosition;
  late final TextEditingController _finalStatus;
  late final TextEditingController _remarks;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    row = ApplicationRow(
      id: e?.id,
      appDate: e?.appDate ?? DateTime.now(),
      position: e?.position,
      department: e?.department,
      status: e?.status ?? 'On Process',
      intvwDate: e?.intvwDate,
      recommendation: e?.recommendation,
      hiredDate: e?.hiredDate,
      finalPosition: e?.finalPosition,
      finalDepartment: e?.finalDepartment,
      finalStatus: e?.finalStatus,
      empStatus: e?.empStatus,
      remarks: e?.remarks,
      assumption: e?.assumption,
    );
    _position = TextEditingController(text: row.position ?? '');
    _status = TextEditingController(text: row.status ?? '');
    _finalPosition = TextEditingController(text: row.finalPosition ?? '');
    _finalStatus = TextEditingController(text: row.finalStatus ?? '');
    _remarks = TextEditingController(text: row.remarks ?? '');
  }

  @override
  void dispose() {
    _position.dispose();
    _status.dispose();
    _finalPosition.dispose();
    _finalStatus.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDate(DateTime? current) =>
      AppDatePicker.show(
        context,
        initialDate: current,
        lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      );

  Widget _dateField(String label, DateTime? value, void Function(DateTime?) set,
      {bool clearable = true}) {
    final fmt = DateFormat('MMM dd, yyyy');
    return Labeled(
      label: label,
      child: SizedBox(
        height: 42,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            side: const BorderSide(color: AppColors.comboBorder),
            backgroundColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () async {
            final picked = await _pickDate(value);
            if (picked != null) setState(() => set(picked));
          },
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value == null ? 'Pick a date...' : fmt.format(value),
                  style: AppTypography.body.copyWith(
                    fontSize: 13,
                    color: value == null ? AppColors.muted : AppColors.ink,
                  ),
                ),
              ),
              if (clearable && value != null)
                GestureDetector(
                  onTap: () => setState(() => set(null)),
                  child: const Icon(Icons.close,
                      size: 14, color: AppColors.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String? value, List<String> options,
      void Function(String?) set, {String? hint, bool allowClear = false, bool filled = true}) {
    final items = {...options, if (value != null && value.trim().isNotEmpty) value}
        .toList()
      ..sort();
    return Labeled(
      label: label,
      child: SearchableDropdown(
        options: items,
        value: (value != null && value.trim().isNotEmpty) ? value : null,
        hint: hint,
        allowClear: allowClear,
        filled: filled,
        onChanged: (v) => setState(() => set(v)),
      ),
    );
  }

  Widget _textField(String label, TextEditingController controller,
      {int maxLines = 1, String? hint, void Function(String)? onChanged}) {
    return Labeled(
      label: label,
      child: TextField(
        controller: controller,
        style: AppTypography.body.copyWith(fontSize: 13),
        maxLines: maxLines,
        minLines: maxLines > 1 ? 2 : null,
        decoration: kInputDecoration.copyWith(
          hintText: hint,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        ),
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lookups;
    final officerNames = l.officers.map((o) => o.recommending).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 720,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.lgAll,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.chipBack,
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Icon(
                      widget.existing == null ? Icons.add : Icons.edit,
                      color: AppColors.chipInk,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.existing == null
                        ? 'Add Application'
                        : 'Edit Application',
                    style: AppTypography.dialogTitle,
                  ),
                ],
              ),
            ),

            // Scrollable body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Application Details section
                    const _SectionLabel(Icons.assignment, 'Application Details'),
                    const SizedBox(height: 12),
                    _SectionCard(
                      icon: Icons.assignment,
                      title: 'Application Details',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _dateField(
                                    'Date of application', row.appDate,
                                    (v) => row.appDate = v,
                                    clearable: false),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: _textField(
                                  'Position applying',
                                  _position,
                                  hint: 'Enter position...',
                                  onChanged: (v) => row.position = v,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: _dropdown('Department', row.department,
                                    l.departments, (v) => row.department = v,
                                    hint: 'Select department...'),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Labeled(
                                  label: 'Status',
                                  child: AutocompleteTextField(
                                    controller: _status,
                                    suggestions: widget.statusSuggestions,
                                    hint: 'Type or pick status...',
                                    onChanged: (v) => row.status = v,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Interview & Outcome section
                    const _SectionLabel(Icons.psychology, 'Interview & Outcome'),
                    const SizedBox(height: 12),
                    _SectionCard(
                      icon: Icons.psychology,
                      title: 'Interview & Outcome',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _dropdown(
                                    'Employment status',
                                    row.empStatus,
                                    empStatusOptions,
                                    (v) => row.empStatus = v,
                                    hint: 'Select status...'),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: _dateField(
                                    'Date of interview', row.intvwDate,
                                    (v) => row.intvwDate = v),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: _dropdown(
                                    'Recommendation',
                                    row.recommendation,
                                    officerNames,
                                    (v) => row.recommendation = v,
                                    hint: 'Select recommendation...'),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: _dateField(
                                    'Date hired', row.hiredDate,
                                    (v) => row.hiredDate = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Final Details section
                    const _SectionLabel(Icons.check_circle, 'Final Details'),
                    const SizedBox(height: 12),
                    _SectionCard(
                      icon: Icons.check_circle,
                      title: 'Final Details',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _textField(
                                  'Final position',
                                  _finalPosition,
                                  hint: 'Enter position...',
                                  onChanged: (v) => row.finalPosition = v,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: _dropdown(
                                    'Final department',
                                    row.finalDepartment,
                                    l.departments,
                                    (v) => row.finalDepartment = v,
                                    hint: 'Select department...'),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: Labeled(
                                  label: 'Final status',
                                  child: AutocompleteTextField(
                                    controller: _finalStatus,
                                    suggestions: widget.statusSuggestions,
                                    hint: 'Type or pick status...',
                                    onChanged: (v) => row.finalStatus = v,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: _dateField(
                                    'Assumption', row.assumption,
                                    (v) => row.assumption = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Remarks section
                    const _SectionLabel(Icons.notes, 'Remarks'),
                    const SizedBox(height: 12),
                    _SectionCard(
                      icon: Icons.notes,
                      title: 'Remarks',
                      child: _textField(
                        '',
                        _remarks,
                        maxLines: 3,
                        hint: 'Additional notes...',
                        onChanged: (v) => row.remarks = v,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(row),
                    child: const Text('Apply'),
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
