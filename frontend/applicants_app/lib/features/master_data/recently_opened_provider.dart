import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One entry in the "jump back to a recent record" list.
class RecentRecord {
  const RecentRecord({
    required this.id,
    required this.displayName,
    required this.openedAt,
  });

  factory RecentRecord.fromJson(Map<String, dynamic> json) => RecentRecord(
        id: json['id'] as int,
        displayName: (json['displayName'] as String?) ?? '',
        openedAt: DateTime.tryParse((json['openedAt'] as String?) ?? '') ??
            DateTime.now(),
      );

  final int id;
  final String displayName;
  final DateTime openedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'openedAt': openedAt.toIso8601String(),
      };
}

/// The last few applicants viewed, created, or edited — newest first, capped
/// at 5, persisted so the list survives a relaunch.
class RecentlyOpenedController extends Notifier<List<RecentRecord>> {
  static const _prefsKey = 'recently-opened';
  static const _cap = 5;
  bool _disposed = false;

  @override
  List<RecentRecord> build() {
    ref.onDispose(() => _disposed = true);
    _init();
    return const [];
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => RecentRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!_disposed) state = list;
    } catch (_) {
      await prefs.remove(_prefsKey);
    }
  }

  void record(int id, String displayName) {
    if (id <= 0 || displayName.trim().isEmpty) return;
    final next = [
      RecentRecord(id: id, displayName: displayName, openedAt: DateTime.now()),
      ...state.where((r) => r.id != id),
    ].take(_cap).toList();
    state = next;
    _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(state.map((r) => r.toJson()).toList()));
  }
}

final recentlyOpenedProvider =
    NotifierProvider<RecentlyOpenedController, List<RecentRecord>>(
        RecentlyOpenedController.new);
