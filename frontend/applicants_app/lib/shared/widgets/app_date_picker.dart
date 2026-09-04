import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';

/// Custom date picker matching the approved wireframe Option 1:
/// - Year/month dropdown selectors with arrow navigation
/// - Quick-jump buttons (Today, Yesterday, 1st of Month)
/// - Cancel/OK footer
/// - Purple header with formatted date
class AppDatePicker extends StatefulWidget {
  const AppDatePicker({
    super.key,
    this.initialDate,
    this.firstDate,
    this.lastDate,
    this.allowClear = true,
  });

  final DateTime? initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool allowClear;

  /// Shows the picker as a popup anchored below [context]'s widget.
  /// Returns the selected date, or null if cancelled/cleared.
  static Future<DateTime?> show(
    BuildContext context, {
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    bool allowClear = true,
  }) {
    return showDialog<DateTime>(
      context: context,
      builder: (context) => AppDatePicker(
        initialDate: initialDate,
        firstDate: firstDate ?? DateTime(1930),
        lastDate: lastDate ?? DateTime(DateTime.now().year + 2, 12, 31),
        allowClear: allowClear,
      ),
    );
  }

  @override
  State<AppDatePicker> createState() => _AppDatePickerState();
}

class _AppDatePickerState extends State<AppDatePicker> {
  late DateTime _current;
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _current = widget.initialDate ?? DateTime.now();
    _year = _current.year;
    _month = _current.month;
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  void _navMonth(int dir) {
    setState(() {
      _month += dir;
      if (_month > 11) { _month = 0; _year++; }
      if (_month < 0) { _month = 11; _year--; }
      _clampDay();
    });
  }

  void _clampDay() {
    final maxDay = DateTime(_year, _month + 1, 0).day;
    if (_current.day > maxDay) {
      _current = DateTime(_year, _month, maxDay);
    } else {
      _current = DateTime(_year, _month, _current.day);
    }
  }

  void _selectDay(int day) {
    setState(() {
      _current = DateTime(_year, _month, day);
    });
  }

  void _quickJump(DateTime date) {
    setState(() {
      _current = date;
      _year = date.year;
      _month = date.month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final first = widget.firstDate;
    final last = widget.lastDate;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 340,
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
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.actionBlue,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SELECT DATE',
                    style: AppTypography.chip.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE, MMM d, yyyy').format(_current),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            // Year/Month selectors + arrows
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              decoration: const BoxDecoration(
                color: AppColors.surface2,
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  // Month dropdown
                  Expanded(
                    child: _Dropdown<int>(
                      value: _month,
                      items: [for (var i = 0; i < 12; i++) i],
                      labelBuilder: (v) => _months[v],
                      onChanged: (v) {
                        if (v != null) setState(() { _month = v; _clampDay(); });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Year dropdown
                  SizedBox(
                    width: 80,
                    child: _Dropdown<int>(
                      value: _year,
                      items: [for (var y = first?.year ?? 1930; y <= (last?.year ?? now.year + 2); y++) y],
                      labelBuilder: (v) => '$v',
                      onChanged: (v) {
                        if (v != null) setState(() { _year = v; _clampDay(); });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Arrow buttons
                  _ArrowButton(
                    icon: Icons.chevron_left,
                    enabled: first == null || DateTime(_year, _month, 1).isAfter(first),
                    onTap: () => _navMonth(-1),
                  ),
                  const SizedBox(width: 2),
                  _ArrowButton(
                    icon: Icons.chevron_right,
                    enabled: last == null || DateTime(_year, _month + 1, 0).isBefore(last),
                    onTap: () => _navMonth(1),
                  ),
                ],
              ),
            ),

            // Weekday headers
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  for (final d in ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'])
                    Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: AppTypography.chip.copyWith(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Calendar grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _CalendarGrid(
                year: _year,
                month: _month,
                selected: _current,
                today: now,
                firstDate: first,
                lastDate: last,
                onSelect: _selectDay,
              ),
            ),

            // Quick jump buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  _QuickButton(
                    label: 'Today',
                    active: _isSameDay(_current, now),
                    onTap: () => _quickJump(now),
                  ),
                  const SizedBox(width: 6),
                  _QuickButton(
                    label: 'Yesterday',
                    active: _isSameDay(_current, DateTime(now.year, now.month, now.day - 1)),
                    onTap: () => _quickJump(DateTime(now.year, now.month, now.day - 1)),
                  ),
                  const SizedBox(width: 6),
                  _QuickButton(
                    label: '1st of Month',
                    active: _current.day == 1,
                    onTap: () => _quickJump(DateTime(_year, _month, 1)),
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.allowClear)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Clear'),
                    ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_current),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ---- Internal sub-widgets ----

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.comboBorder),
        borderRadius: AppRadius.smAll,
      ),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        style: AppTypography.body.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
        items: [
          for (final item in items)
            DropdownMenuItem(value: item, child: Text(labelBuilder(item))),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(icon, color: enabled ? AppColors.ink : AppColors.muted),
        onPressed: enabled ? onTap : null,
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.year,
    required this.month,
    required this.selected,
    required this.today,
    this.firstDate,
    this.lastDate,
    required this.onSelect,
  });

  final int year;
  final int month;
  final DateTime selected;
  final DateTime today;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final firstDayOfWeek = DateTime(year, month, 1).weekday % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final daysInPrevMonth = DateTime(year, month, 0).day;
    final todayNum = today.year == year && today.month == month ? today.day : -1;
    final selectedNum = selected.year == year && selected.month == month ? selected.day : -1;

    final cells = <Widget>[];

    // Previous month trailing days
    for (var i = 0; i < firstDayOfWeek; i++) {
      final day = daysInPrevMonth - firstDayOfWeek + i + 1;
      cells.add(_DayCell(
        day: day,
        muted: true,
        onTap: () {},
      ));
    }

    // Current month days
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final isToday = day == todayNum;
      final isSelected = day == selectedNum;
      final isDisabled = (firstDate != null && date.isBefore(firstDate!)) ||
          (lastDate != null && date.isAfter(lastDate!));
      cells.add(_DayCell(
        day: day,
        today: isToday,
        selected: isSelected,
        disabled: isDisabled,
        onTap: isDisabled ? null : () => onSelect(day),
      ));
    }

    // Next month leading days
    final remaining = 42 - cells.length;
    for (var day = 1; day <= remaining; day++) {
      cells.add(_DayCell(
        day: day,
        muted: true,
        onTap: () {},
      ));
    }

    return GridView.count(
      crossAxisCount: 7,
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      childAspectRatio: 1.0,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    this.muted = false,
    this.today = false,
    this.selected = false,
    this.disabled = false,
    this.onTap,
  });

  final int day;
  final bool muted;
  final bool today;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Color? bgColor;
    Color textColor = AppColors.ink;

    if (selected) {
      bgColor = AppColors.actionBlue;
      textColor = Colors.white;
    } else if (today) {
      bgColor = const Color(0xFFEEF2FF);
      textColor = AppColors.actionBlue;
    }

    if (muted) textColor = AppColors.muted;
    if (disabled) textColor = AppColors.muted;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smAll,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: AppRadius.smAll,
        ),
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 12,
            fontWeight: (today || selected) ? FontWeight.w700 : FontWeight.w400,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smAll,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEEF2FF) : Colors.white,
          border: Border.all(
            color: active ? AppColors.actionBlue : AppColors.line,
          ),
          borderRadius: AppRadius.smAll,
        ),
        child: Text(
          label,
          style: AppTypography.chip.copyWith(
            fontSize: 11,
            color: active ? AppColors.actionBlue : AppColors.muted,
          ),
        ),
      ),
    );
  }
}
