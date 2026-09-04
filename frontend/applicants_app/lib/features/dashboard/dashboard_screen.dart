import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat, DateFormat;

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/shimmer.dart';
import '../applicant_browse/applicant_browse_provider.dart';
import 'dashboard_provider.dart';

void goFiltered(
  BuildContext context,
  WidgetRef ref, {
  bool hired = false,
  String status = '',
  String? municipality,
  DateTime? dateFrom,
  DateTime? dateTo,
}) {
  ref.read(browseFiltersProvider(hired).notifier).update(BrowseFilters(
        status: status,
        municipality: municipality,
        dateFrom: dateFrom,
        dateTo: dateTo,
      ));
  context.go(hired ? '/hired' : '/list');
}

String periodSuffix(String period) => switch (period) {
      'month' => 'THIS MONTH',
      'all' => '(ALL TIME)',
      _ => 'THIS YEAR',
    };

// ─── Period Picker ──────────────────────────────────────────────────────────

class _PeriodPicker extends ConsumerWidget {
  const _PeriodPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardPeriodProvider);
    Widget btn(String value, String label) {
      final active = period == value;
      return GestureDetector(
        onTap: () => ref.read(dashboardPeriodProvider.notifier).set(value),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: active ? AppColors.actionBlue : Colors.transparent,
              borderRadius: AppRadius.smAll,
            ),
            child: Text(label,
                style: AppTypography.helper.copyWith(
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppColors.muted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn('month', 'This month'),
        btn('year', 'This year'),
        btn('all', 'All time'),
      ]),
    );
  }
}

// ─── Dashboard Screen ───────────────────────────────────────────────────────

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardProvider);
    final period = ref.watch(dashboardPeriodProvider);

    if (summary.hasError) {
      return _DashboardError(
        error: summary.error,
        onRetry: () => ref.invalidate(dashboardProvider),
      );
    }

    return summary.when(
      loading: () => const _DashboardSkeleton(),
      error: (err, _) => _DashboardError(
        error: err,
        onRetry: () => ref.invalidate(dashboardProvider),
      ),
      data: (data) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardProvider),
        child: Container(
          color: AppColors.ground,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageHeader(title: 'Dashboard', actions: [_PeriodPicker()]),
                const SizedBox(height: AppSpacing.lg),
                // ── Row 1: Compact stat pills ──
                _StatPills(data: data, period: period),
                const SizedBox(height: AppSpacing.md),
                // ── Row 2: Heatmap + Today's Overview ──
                _HeatmapTodayRow(data: data),
                const SizedBox(height: AppSpacing.md),
                // ── Row 3: Donut + Bar + Municipalities (3 equal cols) ──
                _ThreeColRow(
                  left: AppCard(
                    title: 'Status Distribution',
                    child: _DonutCompact(data: data),
                  ),
                  center: AppCard(
                    title: 'Monthly Trend',
                    subtitle: 'Last 12 months',
                    child: _BarCompact(data: data),
                  ),
                  right: AppCard(
                    title: 'Top Municipalities',
                    trailing: GestureDetector(
                      onTap: () => goFiltered(context, ref),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text('View all',
                            style: AppTypography.helper.copyWith(
                                color: AppColors.actionBlue,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    child: _MuniSection(data: data),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Layout ─────────────────────────────────────────────────────────────────

class _ThreeColRow extends StatelessWidget {
  const _ThreeColRow({required this.left, required this.center, required this.right});
  final Widget left;
  final Widget center;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              left,
              const SizedBox(height: AppSpacing.md),
              center,
              const SizedBox(height: AppSpacing.md),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: center),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _HeatmapTodayRow extends StatelessWidget {
  const _HeatmapTodayRow({required this.data});
  final DashboardSummary data;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMM d, yyyy').format(now);

    return LayoutBuilder(
      builder: (context, constraints) {
        final pillW = (constraints.maxWidth - AppSpacing.md * 3) / 4;
        final narrow = constraints.maxWidth < 900;

        if (narrow) {
          return Column(
            children: [
              AppCard(
                title: 'Contribution Activity',
                subtitle: 'Daily applications over the past year',
                child: _HeatmapSection(data: data),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                title: "Today's Overview",
                subtitle: dateStr,
                padding: const EdgeInsets.all(14),
                child: const _TodayOverviewBody(),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppCard(
                title: 'Contribution Activity',
                subtitle: 'Daily applications over the past year',
                child: _HeatmapSection(data: data),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: pillW,
              child: AppCard(
                title: "Today's Overview",
                subtitle: dateStr,
                padding: const EdgeInsets.all(14),
                child: const _TodayOverviewBody(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TodayOverviewBody extends StatelessWidget {
  const _TodayOverviewBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _TodayStat(
          color: AppColors.actionBlue,
          label: 'New applications',
          value: '23',
          badge: '+8 vs avg',
          badgeBg: AppColors.okBack,
          badgeFg: AppColors.okInk,
        ),
        _TodayStat(
          color: AppColors.okInk,
          label: 'Reviewed',
          value: '15',
        ),
        _TodayStat(
          color: AppColors.warnInk,
          label: 'Interviews',
          value: '4',
          badge: '2 today',
          badgeBg: AppColors.warnBack,
          badgeFg: AppColors.warnInk,
        ),
        _TodayStat(
          color: AppColors.violetInk,
          label: 'Actions needed',
          value: '7',
          badge: '3 urgent',
          badgeBg: AppColors.dangerBack,
          badgeFg: AppColors.danger,
        ),
      ],
    );
  }
}

class _TodayStat extends StatelessWidget {
  const _TodayStat({
    required this.color,
    required this.label,
    required this.value,
    this.badge,
    this.badgeBg,
    this.badgeFg,
  });

  final Color color;
  final String label;
  final String value;
  final String? badge;
  final Color? badgeBg;
  final Color? badgeFg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: AppTypography.caption),
          ),
          Text(
            value,
            style: AppTypography.kpiNumber.copyWith(
              fontSize: 18,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: const BorderRadius.all(Radius.circular(4)),
              ),
              child: Text(
                badge!,
                style: AppTypography.helper.copyWith(
                  color: badgeFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Compact Donut ──────────────────────────────────────────────────────────

class _DonutCompact extends StatelessWidget {
  const _DonutCompact({required this.data});
  final DashboardSummary data;

  static const _colors = [
    AppColors.okInk,
    AppColors.actionBlue,
    AppColors.warnInk,
    AppColors.violetInk,
    AppColors.muted,
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = data.statusBreakdown;
    final total = rows.fold<int>(0, (s, r) => s + r.count);
    if (total == 0) {
      return const Center(
        heightFactor: 4,
        child: Text('No data yet.', style: AppTypography.helper),
      );
    }

    final arcs = <_ArcData>[];
    var start = -math.pi / 2;
    for (var i = 0; i < rows.length; i++) {
      final sweep = (rows[i].count / total) * 2 * math.pi;
      arcs.add(_ArcData(
          color: _colors[i % _colors.length], start: start, sweep: sweep));
      start += sweep;
    }

    return Row(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: CustomPaint(
            painter: _DonutPainter(arcs: arcs),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    NumberFormat('#,##0').format(total),
                    style: AppTypography.kpiNumber.copyWith(
                      fontSize: 16,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Text('Total', style: AppTypography.helper),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _colors[i % _colors.length],
                          borderRadius:
                              const BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(rows[i].label,
                            style: AppTypography.caption,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        '${(rows[i].count / total * 100).round()}%',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Compact Bar ────────────────────────────────────────────────────────────

class _BarCompact extends StatelessWidget {
  const _BarCompact({required this.data});
  final DashboardSummary data;

  @override
  Widget build(BuildContext context) {
    final series = data.applicationsByMonth;
    if (series.isEmpty) {
      return const Center(
        heightFactor: 5,
        child: Text('No applications in the last 12 months.',
            style: AppTypography.helper),
      );
    }
    final max = series.map((e) => e.count).reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final m in series) ...[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${m.count}',
                      style: AppTypography.helper.copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  const SizedBox(height: 3),
                  Container(
                    height: max == 0 ? 2 : (80 * m.count / max),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.actionBlueHover,
                          AppColors.actionBlue
                        ],
                      ),
                      borderRadius: BorderRadius.vertical(
                          top: Radius.circular(AppRadius.sm)),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(DateFormat('MMM').format(m.month),
                      style: AppTypography.helper.copyWith(
                          fontSize: 9, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

// ─── Stat Pills ─────────────────────────────────────────────────────────────

class _StatPills extends ConsumerWidget {
  const _StatPills({required this.data, required this.period});
  final DashboardSummary data;
  final String period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bounds = periodBounds(period);
    return _EvenWrap(
      columns: MediaQuery.sizeOf(context).width >= 1100
          ? 4
          : MediaQuery.sizeOf(context).width >= 700
              ? 2
              : 1,
      children: [
        _StatPill(
          icon: Icons.people_outline,
          iconBg: AppColors.actionBlue.withValues(alpha: .12),
          iconColor: AppColors.actionBlue,
          label: 'Applicants on file',
          value: data.applicantsOnFile,
          onTap: () => goFiltered(context, ref),
        ),
        _StatPill(
          icon: Icons.description_outlined,
          iconBg: AppColors.okInk.withValues(alpha: .12),
          iconColor: AppColors.okInk,
          label: 'Applications ${periodSuffix(period)}',
          value: data.applicationsThisYear,
          onTap: () => goFiltered(
              context, ref, dateFrom: bounds.from, dateTo: bounds.to),
        ),
        _StatPill(
          icon: Icons.check_circle_outline,
          iconBg: AppColors.warnInk.withValues(alpha: .12),
          iconColor: AppColors.warnInk,
          label: 'Hired ${periodSuffix(period)}',
          value: data.hiredThisYear,
          onTap: () => goFiltered(context, ref,
              hired: true, dateFrom: bounds.from, dateTo: bounds.to),
        ),
        _StatPill(
          icon: Icons.hourglass_empty,
          iconBg: AppColors.violetInk.withValues(alpha: .12),
          iconColor: AppColors.violetInk,
          label: 'On process',
          value: data.onProcess,
          onTap: () => goFiltered(context, ref, status: 'process'),
        ),
      ],
    );
  }
}

class _StatPill extends StatefulWidget {
  const _StatPill({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  State<_StatPill> createState() => _StatPillState();
}

class _StatPillState extends State<_StatPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final lifted = widget.onTap != null && _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: lifted ? .12 : .06),
                blurRadius: lifted ? 16 : 8,
                offset: Offset(0, lifted ? 6 : 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.iconBg,
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(widget.icon, size: 18, color: widget.iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NumberFormat('#,##0').format(widget.value),
                      style: AppTypography.kpiNumber.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.label.toUpperCase(),
                      style: AppTypography.helper.copyWith(
                        color: AppColors.muted,
                        letterSpacing: .3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvenWrap extends StatelessWidget {
  const _EvenWrap({required this.columns, required this.children});
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const gap = AppSpacing.md;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileW = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: tileW, child: child),
          ],
        );
      },
    );
  }
}

class _ArcData {
  const _ArcData(
      {required this.color, required this.start, required this.sweep});
  final Color color;
  final double start;
  final double sweep;
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.arcs});
  final List<_ArcData> arcs;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 14;
    const strokeWidth = 22.0;

    for (final arc in arcs) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        arc.start,
        arc.sweep,
        false,
        Paint()
          ..color = arc.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.arcs != arcs;
}



// ─── Heatmap (GitHub-style contribution graph) ──────────────────────────────

class _HeatmapSection extends StatelessWidget {
  const _HeatmapSection({required this.data});
  final DashboardSummary data;

  @override
  Widget build(BuildContext context) {
    if (data.applicationsByDay.isEmpty) {
      return const Center(
        heightFactor: 4,
        child: Text('No data yet.', style: AppTypography.helper),
      );
    }
    return _Heatmap(days: data.applicationsByDay);
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.days});
  final List<DayCount> days;

  // GitHub-style green palette: light → dark
  static const _levels = [
    Color(0xFFEBEDF0), // empty / no data
    Color(0xFF9BE9A8), // 1–25%
    Color(0xFF40C463), // 25–50%
    Color(0xFF30A14E), // 50–75%
    Color(0xFF216E39), // 75–100%
  ];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    // Start from the Sunday 52 weeks ago (GitHub aligns to weeks starting Sunday)
    final startOfWeek = today.subtract(Duration(days: 364 + today.weekday % 7));

    // Build a map of date → count
    final dayMap = <DateTime, int>{};
    var totalContributions = 0;
    for (final d in days) {
      final key = DateTime(d.day.year, d.day.month, d.day.day);
      dayMap[key] = d.count;
      totalContributions += d.count;
    }
    final maxCount = dayMap.values.isEmpty ? 1 : dayMap.values.reduce(math.max);

    // Build 7 rows (Sun–Sat) × 53 columns (weeks)
    // rows[dayOfWeek][weekIndex] = level (0–4)
    final rows = List.generate(7, (_) => <int>[]);
    final weekDates = <DateTime>[]; // first day of each week column

    var cursor = startOfWeek;
    for (var w = 0; w < 53; w++) {
      weekDates.add(cursor);
      for (var d = 0; d < 7; d++) {
        final date = cursor.add(Duration(days: d));
        if (date.isAfter(today)) {
          rows[d].add(-1); // future day — hide
        } else {
          final count = dayMap[DateTime(date.year, date.month, date.day)] ?? 0;
          final level =
              count == 0 ? 0 : (count / maxCount * 4).ceil().clamp(0, 4);
          rows[d].add(level);
        }
      }
      cursor = cursor.add(const Duration(days: 7));
    }

    // Month labels — placed above the first column that contains that month
    final monthPositions = <String, int>{};
    for (var w = 0; w < weekDates.length; w++) {
      final m = weekDates[w].month;
      final label = DateFormat('MMM').format(weekDates[w]);
      if (!monthPositions.containsKey(label) || m != weekDates[(monthPositions[label]!)].month) {
        monthPositions[label] = w;
      }
    }

    const dayLabels = ['', 'Mon', '', 'Wed', '', 'Fri', ''];
    const cellSize = 12.0;
    const cellGap = 3.0;
    const labelWidth = 32.0;
    const colWidth = cellSize + cellGap;
    final totalWeeks = rows[0].length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: labelWidth),
          child: SizedBox(
            height: 16,
            child: Row(
              children: [
                for (var w = 0; w < totalWeeks; w++)
                  SizedBox(
                    width: colWidth,
                    child: monthPositions.containsValue(w)
                        ? Text(
                            monthPositions.entries
                                .firstWhere((e) => e.value == w)
                                .key,
                            style: AppTypography.helper.copyWith(
                                fontSize: 10, color: AppColors.muted),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: (cellSize + cellGap) * 7,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Column(
                  children: [
                    for (var d = 0; d < 7; d++)
                      SizedBox(
                        height: cellSize + cellGap,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              dayLabels[d],
                              style: AppTypography.helper.copyWith(
                                  fontSize: 10, color: AppColors.muted),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: colWidth * totalWeeks,
                    child: Column(
                      children: [
                        for (var d = 0; d < 7; d++)
                          SizedBox(
                            height: cellSize + cellGap,
                            child: Row(
                              children: [
                                for (var w = 0; w < totalWeeks; w++)
                                  SizedBox(
                                    width: colWidth,
                                    height: cellSize,
                                    child: rows[d][w] < 0
                                        ? const SizedBox.shrink()
                                        : Tooltip(
                                            message: _tooltipText(
                                                weekDates[w], d, dayMap),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: _levels[rows[d][w]],
                                                borderRadius:
                                                    const BorderRadius.all(
                                                        Radius.circular(2)),
                                              ),
                                            ),
                                          ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$totalContributions contributions in ${today.year}',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            Row(
              children: [
                Text('Less',
                    style: AppTypography.helper
                        .copyWith(fontSize: 10, color: AppColors.muted)),
                const SizedBox(width: 4),
                for (final c in _levels)
                  Container(
                    width: cellSize,
                    height: cellSize,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius:
                          const BorderRadius.all(Radius.circular(3)),
                    ),
                  ),
                Text('More',
                    style: AppTypography.helper
                        .copyWith(fontSize: 10, color: AppColors.muted)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  String _tooltipText(DateTime weekStart, int dayOfWeek, Map<DateTime, int> dayMap) {
    final date = weekStart.add(Duration(days: dayOfWeek));
    final key = DateTime(date.year, date.month, date.day);
    final count = dayMap[key] ?? 0;
    final dayStr = DateFormat('EEE, MMM d, yyyy').format(date);
    if (count == 0) return 'No applications on $dayStr';
    return '$count application${count == 1 ? '' : 's'} on $dayStr';
  }
}

// ─── Municipalities ─────────────────────────────────────────────────────────

class _MuniSection extends StatelessWidget {
  const _MuniSection({required this.data});
  final DashboardSummary data;

  @override
  Widget build(BuildContext context) {
    final rows = data.topMunicipalities;
    if (rows.isEmpty) {
      return const Center(
        heightFactor: 4,
        child: Text('No data yet.', style: AppTypography.helper),
      );
    }
    final top = rows.take(6).toList();
    final max = top.first.count;
    return Column(
      children: [
        for (var i = 0; i < top.length; i++)
          _MuniRow(
            rank: i + 1,
            label: top[i].label,
            count: top[i].count,
            fraction: max == 0 ? 0 : top[i].count / max,
          ),
      ],
    );
  }
}

class _MuniRow extends StatelessWidget {
  const _MuniRow({
    required this.rank,
    required this.label,
    required this.count,
    required this.fraction,
  });
  final int rank;
  final String label;
  final int count;
  final double fraction;

  ({Color back, Color ink}) get _badge => switch (rank) {
        1 => (back: AppColors.warnBack, ink: AppColors.warnInk),
        2 => (back: AppColors.neutralBack, ink: AppColors.neutralInk),
        3 => (back: const Color(0xFFFED7AA), ink: const Color(0xFF9A3412)),
        _ => (back: AppColors.surface2, ink: AppColors.muted),
      };

  @override
  Widget build(BuildContext context) {
    final b = _badge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: b.back,
              borderRadius: const BorderRadius.all(Radius.circular(6)),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: b.ink),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: AppTypography.caption
                    .copyWith(fontWeight: FontWeight.w500, color: AppColors.ink),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            height: 6,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(3)),
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: AppColors.surface2,
                color: rank <= 3 ? AppColors.actionBlue : AppColors.muted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            child: Text(
              NumberFormat('#,##0').format(count),
              textAlign: TextAlign.right,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Error / Skeleton ───────────────────────────────────────────────────────

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined,
              size: 40, color: AppColors.muted),
          const SizedBox(height: 12),
          const Text('Could not load the dashboard.',
              style: AppTypography.bodyStrong),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text('$error',
                textAlign: TextAlign.center, style: AppTypography.helper),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(title: 'Dashboard', actions: [_PeriodPicker()]),
            const SizedBox(height: AppSpacing.lg),
            // ── Stat pills skeleton ──
            _EvenWrap(
              columns: MediaQuery.sizeOf(context).width >= 1100
                  ? 4
                  : MediaQuery.sizeOf(context).width >= 700
                      ? 2
                      : 1,
              children: List.generate(
                4,
                (_) => Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        SkeletonBox(width: 36, height: 36),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SkeletonBox(width: 60, height: 22),
                            SizedBox(height: 4),
                            SkeletonBox(width: 80, height: 10),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // ── Heatmap + Today skeleton ──
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return Column(
                    children: [
                      _skeletonCard(height: 200),
                      const SizedBox(height: AppSpacing.md),
                      _skeletonCard(height: 200),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _skeletonCard(height: 200)),
                    const SizedBox(width: AppSpacing.md),
                    const SizedBox(
                      width: 320,
                      child: _SkeletonCard(height: 200),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            // ── 3-col skeleton ──
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return Column(
                    children: [
                      _skeletonCard(height: 180),
                      const SizedBox(height: AppSpacing.md),
                      _skeletonCard(height: 180),
                      const SizedBox(height: AppSpacing.md),
                      _skeletonCard(height: 180),
                    ],
                  );
                }
                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _SkeletonCard(height: 180)),
                    SizedBox(width: AppSpacing.md),
                    Expanded(child: _SkeletonCard(height: 180)),
                    SizedBox(width: AppSpacing.md),
                    Expanded(child: _SkeletonCard(height: 180)),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            // ── Activity + Muni skeleton ──
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return Column(
                    children: [
                      _skeletonCard(height: 200),
                      const SizedBox(height: AppSpacing.md),
                      _skeletonCard(height: 200),
                    ],
                  );
                }
                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _SkeletonCard(height: 200)),
                    SizedBox(width: AppSpacing.md),
                    Expanded(flex: 1, child: _SkeletonCard(height: 200)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeletonCard({required double height}) => _SkeletonCard(height: height);
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.line),
      ),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 120, height: 11),
            SizedBox(height: 8),
            SkeletonBox(width: 80, height: 10),
            SizedBox(height: 16),
            Expanded(child: SkeletonBox(width: double.infinity, height: double.infinity)),
          ],
        ),
      ),
    );
  }
}
