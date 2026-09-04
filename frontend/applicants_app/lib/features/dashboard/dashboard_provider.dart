import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../logs/logs_provider.dart';

class MonthCount {
  const MonthCount(this.month, this.count);

  factory MonthCount.fromJson(Map<String, dynamic> json) =>
      MonthCount(DateTime.parse(json['month'] as String), json['count'] as int);

  final DateTime month;
  final int count;
}

class LabelCount {
  const LabelCount(this.label, this.count);

  factory LabelCount.fromJson(Map<String, dynamic> json) =>
      LabelCount(json['label'] as String, json['count'] as int);

  final String label;
  final int count;
}

class DayCount {
  const DayCount(this.day, this.count);

  factory DayCount.fromJson(Map<String, dynamic> json) =>
      DayCount(DateTime.parse(json['day'] as String), json['count'] as int);

  final DateTime day;
  final int count;
}

class DashboardSummary {
  const DashboardSummary({
    required this.applicantsOnFile,
    required this.applicationsThisYear,
    required this.hiredThisYear,
    required this.onProcess,
    required this.applicationsByMonth,
    required this.hiredByMonth,
    required this.onProcessByMonth,
    required this.topMunicipalities,
    required this.statusBreakdown,
    required this.applicationsByDay,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    List<MonthCount> months(String key) => (json[key] as List)
        .map((e) => MonthCount.fromJson(e as Map<String, dynamic>))
        .toList();
    List<LabelCount> labels(String key) => (json[key] as List)
        .map((e) => LabelCount.fromJson(e as Map<String, dynamic>))
        .toList();
    List<DayCount> days(String key) => (json[key] as List)
        .map((e) => DayCount.fromJson(e as Map<String, dynamic>))
        .toList();
    return DashboardSummary(
      applicantsOnFile: json['applicantsOnFile'] as int,
      applicationsThisYear: json['applicationsThisYear'] as int,
      hiredThisYear: json['hiredThisYear'] as int,
      onProcess: json['onProcess'] as int,
      applicationsByMonth: months('applicationsByMonth'),
      hiredByMonth: months('hiredByMonth'),
      onProcessByMonth: months('onProcessByMonth'),
      topMunicipalities: labels('topMunicipalities'),
      statusBreakdown: labels('statusBreakdown'),
      applicationsByDay: days('applicationsByDay'),
    );
  }

  final int applicantsOnFile;
  final int applicationsThisYear;
  final int hiredThisYear;
  final int onProcess;
  final List<MonthCount> applicationsByMonth;
  final List<MonthCount> hiredByMonth;
  final List<MonthCount> onProcessByMonth;
  final List<LabelCount> topMunicipalities;
  final List<LabelCount> statusBreakdown;
  final List<DayCount> applicationsByDay;
}

/// This Month / This Year / All Time — governs the KPI row and the top-
/// municipalities window. The 12-month trend charts stay fixed regardless.
class DashboardPeriodController extends Notifier<String> {
  @override
  String build() => 'year';

  void set(String period) => state = period;
}

final dashboardPeriodProvider =
    NotifierProvider<DashboardPeriodController, String>(
        DashboardPeriodController.new);

/// Mirrors the backend's PeriodBounds so the client can request the exact
/// same window for a drilldown preview / "view full list" handoff.
({DateTime from, DateTime to}) periodBounds(String period) {
  final today = DateTime.now();
  switch (period) {
    case 'month':
      final start = DateTime(today.year, today.month, 1);
      return (from: start, to: DateTime(today.year, today.month + 1, 1));
    case 'all':
      return (from: DateTime(1900, 1, 1), to: DateTime(2100, 1, 1));
    default: // 'year'
      return (from: DateTime(today.year, 1, 1), to: DateTime(today.year + 1, 1, 1));
  }
}

/// Fetches the summary for an explicit period, independent of whatever
/// period the Dashboard screen's own toggle (dashboardPeriodProvider)
/// currently has selected — lets other screens (e.g. the Browse stats row)
/// request e.g. 'all' or 'month' without disturbing the Dashboard's state.
final dashboardSummaryProvider =
    FutureProvider.family<DashboardSummary, String>((ref, period) async {
  final api = ref.read(apiClientProvider);
  final json = await api
      .get('/api/dashboard/summary?period=${Uri.encodeComponent(period)}');
  return DashboardSummary.fromJson(json as Map<String, dynamic>);
});

final dashboardProvider = FutureProvider<DashboardSummary>((ref) {
  final period = ref.watch(dashboardPeriodProvider);
  return ref.watch(dashboardSummaryProvider(period).future);
});

/// Recent activity for the dashboard feed — top 5 entries from the audit log.
final dashboardActivityProvider = FutureProvider<List<AuditEntry>>((ref) async {
  final api = ref.read(apiClientProvider);
  final json = await api.get('/api/audit-log?limit=5') as Map<String, dynamic>;
  return (json['rows'] as List)
      .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
      .toList();
});
