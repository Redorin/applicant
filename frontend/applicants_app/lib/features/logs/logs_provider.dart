import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.detail,
    required this.changedAt,
    required this.changedBy,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: json['id'] as int,
        entityType: json['entityType'] as String,
        entityId: json['entityId'] as int,
        action: json['action'] as String,
        detail: json['detail'] as String?,
        changedAt: DateTime.parse(json['changedAt'] as String),
        changedBy: json['changedBy'] as String?,
      );

  final int id;
  final String entityType;
  final int entityId;
  final String action;
  final String? detail;
  final DateTime changedAt;
  final String? changedBy;

  /// Plain-language summary for the Logs screen — every action the app
  /// records maps to one line here so the list reads like a sentence
  /// instead of raw entityType/action codes.
  String get summary {
    final who = (changedBy ?? '').isEmpty ? 'System' : changedBy!;
    switch ('$entityType.$action') {
      case 'auth.login':
        return '$who signed in';
      case 'auth.login_failed':
        return 'Failed sign-in attempt${detail == null || detail!.isEmpty ? '' : ' ("$detail")'}';
      case 'auth.logout':
        return '$who signed out';
      case 'auth.change_password':
        return '$who changed their password';
      case 'auth.update_profile':
        return '$who updated their profile';
      case 'masterdata.insert':
        return '$who added applicant${detail == null ? '' : ' — $detail'}';
      case 'masterdata.update':
        return '$who updated applicant${detail == null ? '' : ' — $detail'}';
      case 'masterdata.archive':
        return '$who archived applicant #$entityId';
      case 'masterdata.restore':
        return '$who restored applicant #$entityId';
      case 'masterdata.import':
        return '$who imported a batch${detail == null ? '' : ' — $detail'}';
      case 'status.merge':
        return '$who merged a status spelling${detail == null ? '' : ' — $detail'}';
      case 'lookup.quick_add':
        return '$who added a lookup value${detail == null ? '' : ' — $detail'}';
      case 'lookup.batch_save':
        return '$who edited parameters${detail == null ? '' : ' — $detail'}';
      case 'report.generate':
        return '$who generated a report${detail == null ? '' : ' — $detail'}';
      case 'report.save_copy':
        return '$who saved a copy of a report${detail == null ? '' : ' — $detail'}';
      case 'application.hire':
        return '$who hired applicant${detail == null ? '' : ' — $detail'}';
      case 'application.unhire':
        return '$who moved an applicant back to the list';
      case 'application.bulk-status':
        return '$who updated status${detail == null ? '' : ' — $detail'}';
      default:
        return '$who — $entityType $action${detail == null ? '' : ' ($detail)'}';
    }
  }
}

/// The Activity Logs screen's "Action" dropdown — the spec's 6 clean labels,
/// each mapped server-side to its real entityType/action pair(s) (see
/// AuditLogService.Buckets in the backend), plus "Other" so every real log
/// entry always has a bucket to land in, even ones invented after this list
/// was written.
const kLogBuckets = {
  'statusChange': 'Status Change',
  'applicantAdded': 'Applicant Added',
  'applicantEdited': 'Applicant Edited',
  'hired': 'Hired',
  'reportGenerated': 'Report Generated',
  'login': 'Login',
  'other': 'Other',
};

/// Display names for the known seeded accounts (mirrors
/// MaintenanceService.SeedUsers on the backend) — used only to make the
/// User filter dropdown and table column readable; filtering itself still
/// uses the real username.
const kUserDisplayNames = {
  'des': 'Lourdes C. Samson',
  'ann': 'Andrea Dawn Criselda T. Vinluan',
  'kath': 'Kathlyn Joy DC. Torres',
  'hara': 'Harah Karylle S. Pascua',
  'lyndon': 'Lyndon P. Felix',
  'red': 'Reddrick M. Gonzales',
};

String displayNameFor(String? username) =>
    username == null ? 'System' : (kUserDisplayNames[username] ?? username);

class LogsFilters {
  const LogsFilters({this.search = '', this.bucket, this.changedBy, this.page = 0});

  final String search;
  final String? bucket;
  final String? changedBy;
  final int page;

  bool get isEmpty => search.isEmpty && bucket == null && changedBy == null;

  LogsFilters copyWith({
    String? search,
    String? bucket,
    bool clearBucket = false,
    String? changedBy,
    bool clearChangedBy = false,
    int? page,
  }) =>
      LogsFilters(
        search: search ?? this.search,
        bucket: clearBucket ? null : (bucket ?? this.bucket),
        changedBy: clearChangedBy ? null : (changedBy ?? this.changedBy),
        // Any filter change resets pagination unless page is set explicitly.
        page: page ?? 0,
      );
}

class LogsFiltersNotifier extends Notifier<LogsFilters> {
  @override
  LogsFilters build() => const LogsFilters();

  void update(LogsFilters filters) => state = filters;

  void clear() => state = const LogsFilters();
}

final logsFiltersProvider =
    NotifierProvider<LogsFiltersNotifier, LogsFilters>(LogsFiltersNotifier.new);

const logsPageSize = 50;

class LogsPage {
  const LogsPage({required this.total, required this.rows});
  final int total;
  final List<AuditEntry> rows;
}

/// Every notable thing done in the app — sign-ins, record saves/archives,
/// status merges, parameter edits, imports, hires, report generation —
/// paged newest-first from the backend's shared audit_log table, filtered
/// by the current LogsFilters.
final logsResultsProvider = FutureProvider<LogsPage>((ref) async {
  final filters = ref.watch(logsFiltersProvider);
  final api = ref.read(apiClientProvider);
  final query = [
    if (filters.search.trim().isNotEmpty)
      'search=${Uri.encodeComponent(filters.search.trim())}',
    if (filters.bucket != null) 'bucket=${Uri.encodeComponent(filters.bucket!)}',
    if (filters.changedBy != null) 'changedBy=${Uri.encodeComponent(filters.changedBy!)}',
    'offset=${filters.page * logsPageSize}',
    'limit=$logsPageSize',
  ].join('&');
  final json = await api.get('/api/audit-log?$query') as Map<String, dynamic>;
  return LogsPage(
    total: json['total'] as int,
    rows: (json['rows'] as List)
        .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
});

/// Distinct usernames that have actually logged activity — backs the User
/// filter dropdown so it never lists an account that's never done anything
/// (or hides one that isn't in [kUserDisplayNames] yet).
final logUsersProvider = FutureProvider<List<String>>((ref) async {
  final api = ref.read(apiClientProvider);
  final json = await api.get('/api/audit-log/users');
  return (json as List).cast<String>();
});


