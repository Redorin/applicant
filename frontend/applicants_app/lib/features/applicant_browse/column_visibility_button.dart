import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_button_styles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import 'browse_column_prefs_provider.dart';

/// Small toolbar button opening a checklist of Browse columns to show/hide.
/// Unlike PopupMenuButton, this stays open across multiple taps so several
/// columns can be toggled in one go.
class ColumnVisibilityButton extends StatefulWidget {
  const ColumnVisibilityButton({super.key, required this.hiredOnly});
  final bool hiredOnly;

  @override
  State<ColumnVisibilityButton> createState() =>
      _ColumnVisibilityButtonState();
}

class _ColumnVisibilityButtonState extends State<ColumnVisibilityButton> {
  final _layerLink = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _toggleOpen() {
    if (_entry != null) {
      _hide();
    } else {
      _entry = _build();
      Overlay.of(context).insert(_entry!);
    }
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  OverlayEntry _build() {
    final keys = widget.hiredOnly
        ? kBrowseColumns.keys
            .where((k) => !{'position', 'office', 'dateApplied'}.contains(k))
        : kBrowseColumns.keys
            .where((k) => !{'dateHired', 'finalPosition', 'finalDepartment'}
                .contains(k));

    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Tap-outside-to-close barrier.
          Positioned.fill(
            child: GestureDetector(
                onTap: _hide, behavior: HitTestBehavior.translucent),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 40),
            child: Material(
              elevation: 6,
              borderRadius: AppRadius.mdAll,
              child: Container(
                width: 230,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: AppRadius.mdAll,
                ),
                child: Consumer(
                  builder: (context, ref, _) {
                    final hidden = ref.watch(browseColumnPrefsProvider);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding:
                              EdgeInsets.fromLTRB(14, 6, 14, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('SHOW COLUMNS', style: AppTypography.sectionTitle),
                          ),
                        ),
                        for (final key in keys)
                          InkWell(
                            onTap: () => ref
                                .read(browseColumnPrefsProvider.notifier)
                                .toggle(key),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 2),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: !hidden.contains(key),
                                    onChanged: (_) => ref
                                        .read(browseColumnPrefsProvider
                                            .notifier)
                                        .toggle(key),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Text(kBrowseColumns[key]!, style: AppTypography.body),
                                ],
                              ),
                            ),
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
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextButton.icon(
        style: AppButtonStyles.chrome,
        icon: const Icon(Icons.view_column_outlined, size: 15),
        label: const Text('Columns'),
        onPressed: _toggleOpen,
      ),
    );
  }
}
