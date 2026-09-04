import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';

class StatusVariant {
  const StatusVariant(this.status, this.inStatus, this.inFinalStatus);

  factory StatusVariant.fromJson(Map<String, dynamic> json) => StatusVariant(
        json['status'] as String,
        json['inStatus'] as int,
        json['inFinalStatus'] as int,
      );

  final String status;
  final int inStatus;
  final int inFinalStatus;

  int get total => inStatus + inFinalStatus;
}

/// Every distinct status spelling in the database, with usage counts.
final statusVariantsProvider = FutureProvider<List<StatusVariant>>((ref) async {
  final api = ref.read(apiClientProvider);
  final json = await api.get('/api/statuses/') as List;
  return json
      .map((e) => StatusVariant.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Just the spellings — suggestions for status autocomplete fields.
final statusNamesProvider = Provider<List<String>>((ref) {
  final variants = ref.watch(statusVariantsProvider).value ?? [];
  return [for (final v in variants) v.status];
});
