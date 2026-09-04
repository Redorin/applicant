import 'package:flutter/material.dart';

import '../../core/theme/app_button_styles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/escape_to_close.dart';
import '../../shared/widgets/hover_scale.dart';

enum ExportFormat { pdf, excel, csv }

enum ExportScope { all, filtered, selected }

class ExportChoice {
  const ExportChoice({
    required this.format,
    required this.scope,
    required this.includeHeaderRow,
    required this.includeTimestamps,
  });

  final ExportFormat format;
  final ExportScope scope;
  final bool includeHeaderRow;
  final bool includeTimestamps;
}

/// Format/scope/options modal that replaces the old straight-to-PDF Export
/// button. PDF selections still flow through the existing report pipeline
/// (see `_exportViaModal` in applicant_browse_screen.dart); Excel/CSV are
/// real exports via browse_export_writer.dart. Returns `null` on
/// Cancel/Escape/backdrop-tap.
Future<ExportChoice?> showExportModal(
  BuildContext context, {
  required bool hasSelection,
}) {
  return showDialog<ExportChoice>(
    context: context,
    builder: (context) => EscapeToClose(
      child: Dialog(
        insetPadding: const EdgeInsets.all(28),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        child: Semantics(
          namesRoute: true,
          scopesRoute: true,
          explicitChildNodes: true,
          label: 'Export applicants dialog',
          child: _ExportModalBody(hasSelection: hasSelection),
        ),
      ),
    ),
  );
}

class _ExportModalBody extends StatefulWidget {
  const _ExportModalBody({required this.hasSelection});

  final bool hasSelection;

  @override
  State<_ExportModalBody> createState() => _ExportModalBodyState();
}

class _ExportModalBodyState extends State<_ExportModalBody> {
  ExportFormat _format = ExportFormat.pdf;
  late ExportScope _scope = widget.hasSelection
      ? ExportScope.selected
      : ExportScope.all;
  bool _includeHeaderRow = true;
  bool _includeTimestamps = false;

  @override
  Widget build(BuildContext context) {
    final optionsEnabled = _format != ExportFormat.pdf;

    return SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 46,
            color: AppColors.navy,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.download_outlined,
                  color: Colors.white,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Export applicants',
                    style: AppTypography.bodyStrong.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
                Semantics(
                  label: 'Close',
                  button: true,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('FORMAT', style: AppTypography.sectionTitle),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _FormatCard(
                          icon: Icons.picture_as_pdf_outlined,
                          label: 'PDF',
                          description: 'Formatted report',
                          selected: _format == ExportFormat.pdf,
                          onTap: () =>
                              setState(() => _format = ExportFormat.pdf),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _FormatCard(
                          icon: Icons.grid_on_outlined,
                          label: 'Excel',
                          description: 'Spreadsheet (.xlsx)',
                          selected: _format == ExportFormat.excel,
                          onTap: () =>
                              setState(() => _format = ExportFormat.excel),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _FormatCard(
                          icon: Icons.description_outlined,
                          label: 'CSV',
                          description: 'Plain data (.csv)',
                          selected: _format == ExportFormat.csv,
                          onTap: () =>
                              setState(() => _format = ExportFormat.csv),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('SCOPE', style: AppTypography.sectionTitle),
                  RadioGroup<ExportScope>(
                    groupValue: _scope,
                    onChanged: (v) => setState(() => _scope = v!),
                    child: Column(
                      children: [
                        const RadioListTile<ExportScope>(
                          value: ExportScope.all,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: AppColors.actionBlue,
                          title: Text('All records'),
                        ),
                        const RadioListTile<ExportScope>(
                          value: ExportScope.filtered,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: AppColors.actionBlue,
                          title: Text('Filtered results'),
                        ),
                        RadioListTile<ExportScope>(
                          value: ExportScope.selected,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: AppColors.actionBlue,
                          enabled: widget.hasSelection,
                          title: Text(
                            'Selected rows',
                            style: TextStyle(
                              color: widget.hasSelection
                                  ? null
                                  : AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('OPTIONS', style: AppTypography.sectionTitle),
                  CheckboxListTile(
                    value: _includeHeaderRow,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.actionBlue,
                    title: Text(
                      'Include header row',
                      style: TextStyle(
                        color: optionsEnabled ? null : AppColors.muted,
                      ),
                    ),
                    onChanged: optionsEnabled
                        ? (v) => setState(() => _includeHeaderRow = v ?? true)
                        : null,
                  ),
                  CheckboxListTile(
                    value: _includeTimestamps,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.actionBlue,
                    title: Text(
                      'Include timestamps',
                      style: TextStyle(
                        color: optionsEnabled ? null : AppColors.muted,
                      ),
                    ),
                    onChanged: optionsEnabled
                        ? (v) => setState(() => _includeTimestamps = v ?? false)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  style: AppButtonStyles.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.sm),
                HoverScale(
                  glow: true,
                  child: OutlinedButton(
                    style: AppButtonStyles.tonal,
                    onPressed: () => Navigator.of(context).pop(
                      ExportChoice(
                        format: _format,
                        scope: _scope,
                        includeHeaderRow: _includeHeaderRow,
                        includeTimestamps: _includeTimestamps,
                      ),
                    ),
                    child: const Text('Export'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatCard extends StatefulWidget {
  const _FormatCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FormatCard> createState() => _FormatCardState();
}

class _FormatCardState extends State<_FormatCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.accentSoft
                : _hover
                ? AppColors.selectionSoft
                : AppColors.surface,
            border: Border.all(
              color: widget.selected ? AppColors.actionBlue : AppColors.line,
              width: widget.selected ? 1.4 : 1,
            ),
            borderRadius: AppRadius.mdAll,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 22,
                color: widget.selected ? AppColors.actionBlue : AppColors.muted,
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                style: AppTypography.bodyStrong.copyWith(
                  color: widget.selected ? AppColors.ink : AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.description,
                textAlign: TextAlign.center,
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
