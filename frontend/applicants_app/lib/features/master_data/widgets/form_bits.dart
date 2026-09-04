import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_button_styles.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';

/// Section card matching the approved wireframe: uppercase muted title,
/// hairline underline, then content. Thin alias over the shared [AppCard]
/// so master-data forms keep their existing call sites/name.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(title: title, child: child);
}

/// Entered values render in ink for maximum readability.
const kValueStyle = AppTypography.body;

/// Shared InputDecoration for TextFields to match SearchableDropdown height.
/// Uses the same padding, borders, and density as the DropdownMenu.
final kInputDecoration = InputDecoration(
  isDense: true,
  filled: true,
  fillColor: AppColors.surface,
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
  suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
  border: OutlineInputBorder(
    borderRadius: AppRadius.smAll,
    borderSide: const BorderSide(color: AppColors.line),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: AppRadius.smAll,
    borderSide: const BorderSide(color: AppColors.line),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: AppRadius.smAll,
    borderSide: const BorderSide(color: AppColors.selectedBorder, width: 1.4),
  ),
);

/// Small labeled field wrapper for consistent label styling.
/// `required` shows a red asterisk; unmarked fields are optional.
class Labeled extends StatelessWidget {
  const Labeled(
      {super.key, required this.label, required this.child, this.required = false});
  final String label;
  final Widget child;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: label.toUpperCase(),
            style: AppTypography.fieldLabel,
            children: [
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// Free-text field with type-ahead suggestions (used for status fields where
/// any text is allowed but existing spellings should be encouraged).
class AutocompleteTextField extends StatefulWidget {
  const AutocompleteTextField({
    super.key,
    required this.controller,
    required this.suggestions,
    required this.onChanged,
    this.hint,
  });

  final TextEditingController controller;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  State<AutocompleteTextField> createState() => _AutocompleteTextFieldState();
}

class _AutocompleteTextFieldState extends State<AutocompleteTextField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final probe = value.text.trim().toLowerCase();
        if (probe.isEmpty) return widget.suggestions;
        return widget.suggestions
            .where((s) => s.toLowerCase().contains(probe));
      },
      onSelected: widget.onChanged,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
          TextField(
        controller: controller,
        focusNode: focusNode,
        style: kValueStyle,
        decoration: kInputDecoration.copyWith(hintText: widget.hint),
        onChanged: widget.onChanged,
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          borderRadius: AppRadius.smAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260, maxWidth: 420),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: options.length,
              itemBuilder: (context, i) {
                final option = options.elementAt(i);
                return InkWell(
                  onTap: () => onSelected(option),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    child: Text(option, style: kValueStyle),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared, computed-once style for every dropdown entry — previously
/// `MenuItemButton.styleFrom(textStyle: kValueStyle)` was called fresh for
/// every single option on every build, allocating a new ButtonStyle object
/// per entry for no reason (the style never varies between options).
final _kDropdownEntryStyle = MenuItemButton.styleFrom(textStyle: kValueStyle);

/// Type-to-filter dropdown replacing every plain dropdown in the app.
class SearchableDropdown extends StatefulWidget {
  const SearchableDropdown({
    super.key,
    required this.options,
    required this.onChanged,
    this.value,
    this.hint,
    this.allowClear = true,
    this.filled = true,
  });

  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? hint;
  final bool allowClear;
  final bool filled;

  @override
  State<SearchableDropdown> createState() => _SearchableDropdownState();
}

class _SearchableDropdownState extends State<SearchableDropdown> {
  late List<DropdownMenuEntry<String?>> _entries = _buildEntries();

  List<DropdownMenuEntry<String?>> _buildEntries() => [
        for (final o in widget.options)
          DropdownMenuEntry<String?>(value: o, label: o, style: _kDropdownEntryStyle),
      ];

  @override
  void didUpdateWidget(SearchableDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.options, widget.options) ||
        oldWidget.allowClear != widget.allowClear) {
      _entries = _buildEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => DropdownMenu<String?>(
        initialSelection: widget.options.contains(widget.value) ? widget.value : null,
        width: constraints.maxWidth.isFinite ? constraints.maxWidth : 260,
        requestFocusOnTap: true,
        enableFilter: true,
        enableSearch: true,
        menuHeight: 340,
        hintText: widget.hint ?? 'Type to search…',
        textStyle: kValueStyle,
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: widget.filled
              ? (widget.value == null ? AppColors.inputEmptyBg : AppColors.surface)
              : Colors.transparent,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          border: OutlineInputBorder(
            borderRadius: AppRadius.smAll,
            borderSide: const BorderSide(color: AppColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.smAll,
            borderSide: const BorderSide(color: AppColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.smAll,
            borderSide:
                const BorderSide(color: AppColors.selectedBorder, width: 1.4),
          ),
        ),
        dropdownMenuEntries: _entries,
        onSelected: widget.onChanged,
      ),
    );
  }
}

/// Info chip (Age, District) — InfoBack/InfoInk pair from Theme.cs.
class InfoChip extends StatelessWidget {
  const InfoChip(this.text, {super.key, this.warn = false});
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: warn ? AppColors.warnBack : AppColors.infoBack,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        text,
        style: AppTypography.chip.copyWith(
          color: warn ? AppColors.warnInk : AppColors.infoInk,
        ),
      ),
    );
  }
}

/// Formats a contact number live as the user types —
/// accepts both mobile (09XX XXX XXXX) and telephone (XXXX XXX XXXX) formats.
class ContactNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 11 ? digits.substring(0, 11) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 4 || i == 7) buffer.write(' ');
      buffer.write(capped[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The single aggregated validation-error dialog, like the old themed dialog.
Future<void> showValidationErrors(BuildContext context, List<String> errors) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warnInk, size: 22),
          SizedBox(width: 8),
          Text('Cannot save yet'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in errors)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ',
                        style: TextStyle(color: AppColors.danger)),
                    Expanded(child: Text(e)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Destructive-action confirm where "No" is the safe default focus.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Yes',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(message),
      ),
      actions: [
        ElevatedButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('No, keep it'),
        ),
        OutlinedButton(
          style: AppButtonStyles.danger,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
