import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';

class BrowseRow {
  BrowseRow({
    this.id,
    required this.masterdataId,
    required this.applicant,
    this.municipality,
    this.position,
    this.department,
    this.appDate,
    this.status,
    this.hiredDate,
    this.finalPosition,
    this.finalDepartment,
    this.recommendation,
    this.course,
  });

  factory BrowseRow.fromJson(Map<String, dynamic> json) {
    DateTime? d(String key) =>
        json[key] == null ? null : DateTime.parse(json[key] as String);
    return BrowseRow(
      id: json['id'] as int?,
      masterdataId: json['masterdataId'] as int,
      applicant: (json['applicant'] as String?) ?? '',
      municipality: json['municipality'] as String?,
      position: json['position'] as String?,
      department: json['department'] as String?,
      appDate: d('appDate'),
      status: json['status'] as String?,
      hiredDate: d('hiredDate'),
      finalPosition: json['finalPosition'] as String?,
      finalDepartment: json['finalDepartment'] as String?,
      recommendation: json['recommendation'] as String?,
      course: json['course'] as String?,
    );
  }

  final int? id;
  final int masterdataId;
  final String applicant;
  final String? municipality;
  final String? position;
  final String? department;
  final DateTime? appDate;
  String? status;
  DateTime? hiredDate;
  String? finalPosition;
  String? finalDepartment;
  final String? recommendation;
  final String? course;
}

const browsePageSize = 100;

class BrowseFilters {
  const BrowseFilters({
    this.name = '',
    this.status = '',
    this.municipality,
    this.office,
    this.course,
    this.eligibility,
    this.recommendation,
    this.dateFrom,
    this.dateTo,
    this.page = 0,
    this.sortBy,
    this.sortDir = 'desc',
  });

  final String name;
  final String status;
  final String? municipality;
  final String? office;
  final String? course;
  final String? eligibility;
  final String? recommendation;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// Zero-based page index; changing any filter resets to page 0.
  final int page;

  /// null = server default (newest application first). One of
  /// appDate/surname/municipality/status when a column header was clicked.
  final String? sortBy;
  final String sortDir;

  bool get isEmpty =>
      name.isEmpty &&
      status.isEmpty &&
      municipality == null &&
      office == null &&
      course == null &&
      eligibility == null &&
      recommendation == null &&
      dateFrom == null &&
      dateTo == null;

  BrowseFilters copyWith({
    String? name,
    String? status,
    String? municipality,
    bool clearMunicipality = false,
    String? office,
    bool clearOffice = false,
    String? course,
    bool clearCourse = false,
    String? eligibility,
    bool clearEligibility = false,
    String? recommendation,
    bool clearRecommendation = false,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearDates = false,
    int? page,
    String? sortBy,
    String? sortDir,
  }) =>
      BrowseFilters(
        name: name ?? this.name,
        status: status ?? this.status,
        municipality:
            clearMunicipality ? null : (municipality ?? this.municipality),
        office: clearOffice ? null : (office ?? this.office),
        course: clearCourse ? null : (course ?? this.course),
        eligibility: clearEligibility ? null : (eligibility ?? this.eligibility),
        recommendation: clearRecommendation ? null : (recommendation ?? this.recommendation),
        dateFrom: clearDates ? null : (dateFrom ?? this.dateFrom),
        dateTo: clearDates ? null : (dateTo ?? this.dateTo),
        // Any filter change resets pagination unless page is set explicitly.
        page: page ?? 0,
        sortBy: sortBy ?? this.sortBy,
        sortDir: sortDir ?? this.sortDir,
      );

  /// Clicking a column header: same column → flip direction; different
  /// column → switch to it, defaulting to descending.
  BrowseFilters toggleSort(String column) => copyWith(
        sortBy: column,
        sortDir: sortBy == column && sortDir == 'desc' ? 'asc' : 'desc',
        page: 0,
      );

  String toQuery(bool hiredOnly, {int? overridePageSize}) {
    final size = overridePageSize ?? browsePageSize;
    final parts = <String>[
      'hiredOnly=$hiredOnly',
      'offset=${overridePageSize == null ? page * browsePageSize : 0}',
      'pageSize=$size',
    ];
    if (name.trim().isNotEmpty) {
      parts.add('name=${Uri.encodeComponent(name.trim())}');
    }
    if (status.trim().isNotEmpty) {
      parts.add('status=${Uri.encodeComponent(status.trim())}');
    }
    if (municipality != null) {
      parts.add('municipality=${Uri.encodeComponent(municipality!)}');
    }
    if (office != null) {
      parts.add('office=${Uri.encodeComponent(office!)}');
    }
    if (course != null) {
      parts.add('course=${Uri.encodeComponent(course!)}');
    }
    if (eligibility != null) {
      parts.add('eligibility=${Uri.encodeComponent(eligibility!)}');
    }
    if (recommendation != null) {
      parts.add('recommendation=${Uri.encodeComponent(recommendation!)}');
    }
    if (dateFrom != null) {
      parts.add('dateFrom=${dateFrom!.toIso8601String()}');
    }
    if (dateTo != null) {
      parts.add('dateTo=${dateTo!.toIso8601String()}');
    }
    if (sortBy != null) {
      parts.add('sortBy=${Uri.encodeComponent(sortBy!)}');
      parts.add('sortDir=${Uri.encodeComponent(sortDir)}');
    }
    return parts.join('&');
  }
}

class BrowseFiltersNotifier extends Notifier<BrowseFilters> {
  @override
  BrowseFilters build() => const BrowseFilters();

  void update(BrowseFilters filters) => state = filters;

  void clear() => state = const BrowseFilters();
}

final _listFiltersProvider =
    NotifierProvider<BrowseFiltersNotifier, BrowseFilters>(
        BrowseFiltersNotifier.new);
final _hiredFiltersProvider =
    NotifierProvider<BrowseFiltersNotifier, BrowseFilters>(
        BrowseFiltersNotifier.new);

/// Filter state per view — the List and Hired tabs keep separate filters,
/// like the two applicantbrowse instances in the old app.
NotifierProvider<BrowseFiltersNotifier, BrowseFilters> browseFiltersProvider(
        bool hiredOnly) =>
    hiredOnly ? _hiredFiltersProvider : _listFiltersProvider;

class BrowsePage {
  const BrowsePage({required this.total, required this.rows});
  final int total;
  final List<BrowseRow> rows;
}

/// Query results reactively follow the filters (debounced in the UI).
final browseResultsProvider =
    FutureProvider.family<BrowsePage, bool>((ref, hiredOnly) async {
  final filters = ref.watch(browseFiltersProvider(hiredOnly));
  final api = ref.read(apiClientProvider);
  final json = await api.get('/api/browse/?${filters.toQuery(hiredOnly)}')
      as Map<String, dynamic>;
  return BrowsePage(
    total: json['total'] as int,
    rows: (json['rows'] as List)
        .map((e) => BrowseRow.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
});

/// Distinct municipality values present in the data (legacy included).
final browseMunicipalitiesProvider = FutureProvider<List<String>>((ref) async {
  final api = ref.read(apiClientProvider);
  final json = await api.get('/api/browse/municipalities');
  return (json as List).cast<String>();
});

/// Full result set for "All records"/"Filtered results" export, independent
/// of the current page — a sibling of fetchAllLogsForExport in
/// lib/features/logs/logs_provider.dart. `ignoreFilters` drops the current
/// filter set entirely (for "All records"); otherwise the current
/// [BrowseFilters] apply (for "Filtered results"). Capped at 10,000 rows —
/// analogous to logs' existing 5,000-row export cap, not a completeness
/// guarantee for very large result sets.
Future<List<BrowseRow>> fetchAllBrowseRows(
  dynamic api,
  BrowseFilters filters,
  bool hiredOnly, {
  bool ignoreFilters = false,
}) async {
  final f = ignoreFilters ? const BrowseFilters() : filters;
  final json = await api.get(
    '/api/browse/?${f.toQuery(hiredOnly, overridePageSize: 10000)}',
    timeout: const Duration(seconds: 90),
  ) as Map<String, dynamic>;
  return (json['rows'] as List)
      .map((e) => BrowseRow.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Apply one status to many applications at once (row checkboxes' bulk-action
/// bar, and the single-row Reject button which just calls this with one id).
Future<void> applyBulkStatus(
    dynamic api, List<int> applicationIds, String status) async {
  await api.post('/api/browse/bulk-status', body: {
    'applicationIds': applicationIds,
    'status': status,
  });
}
