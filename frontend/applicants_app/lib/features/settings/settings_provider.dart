import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../lookups/lookups_provider.dart';

/// Column kinds the generic settings table can edit.
enum SettingsColumnType { text, provincePicker }

class SettingsColumn {
  const SettingsColumn(this.field, this.label,
      {this.type = SettingsColumnType.text, this.width = 220});
  final String field;
  final String label;
  final SettingsColumnType type;
  final double width;
}

class SettingsTabConfig {
  const SettingsTabConfig({
    required this.key,
    required this.label,
    required this.columns,
  });

  /// Also the API path segment: /api/lookups/{key} and /api/lookups/{key}/batch.
  final String key;
  final String label;
  final List<SettingsColumn> columns;
}

const settingsTabs = [
  SettingsTabConfig(
    key: 'municipals',
    label: 'Municipality',
    columns: [
      SettingsColumn('municipal', 'City / municipality', width: 240),
      SettingsColumn('district', 'District', width: 140),
      SettingsColumn('provinceId', 'Province',
          type: SettingsColumnType.provincePicker, width: 200),
    ],
  ),
  SettingsTabConfig(
    key: 'eligibilities',
    label: 'Eligibility',
    columns: [SettingsColumn('value', 'Eligibility title', width: 420)],
  ),
  SettingsTabConfig(
    key: 'recommendation',
    label: 'Recommending officers',
    columns: [
      SettingsColumn('recommending', 'Name', width: 240),
      SettingsColumn('designation', 'Designation', width: 220),
      SettingsColumn('remarks', 'Remarks', width: 220),
    ],
  ),
  SettingsTabConfig(
    key: 'departments',
    label: 'Departments',
    columns: [
      SettingsColumn('value', 'Offices and hospitals', width: 420)
    ],
  ),
  SettingsTabConfig(
    key: 'education',
    label: 'Education',
    columns: [SettingsColumn('value', 'Courses', width: 420)],
  ),
  SettingsTabConfig(
    key: 'schools',
    label: 'Schools',
    columns: [SettingsColumn('value', 'School graduated from', width: 420)],
  ),
  SettingsTabConfig(
    key: 'provinces',
    label: 'Province',
    columns: [
      SettingsColumn('province', 'Province name', width: 240),
      SettingsColumn('region', 'Region', width: 200),
    ],
  ),
];

class SettingsTabState {
  const SettingsTabState({
    this.rows = const [],
    this.deleteIds = const [],
    this.dirty = false,
    this.loaded = false,
  });

  final List<Map<String, dynamic>> rows;
  final List<int> deleteIds;
  final bool dirty;
  final bool loaded;

  SettingsTabState copyWith({
    List<Map<String, dynamic>>? rows,
    List<int>? deleteIds,
    bool? dirty,
    bool? loaded,
  }) =>
      SettingsTabState(
        rows: rows ?? this.rows,
        deleteIds: deleteIds ?? this.deleteIds,
        dirty: dirty ?? this.dirty,
        loaded: loaded ?? this.loaded,
      );
}

class SettingsState {
  const SettingsState({this.tabs = const {}, this.isSaving = false});
  final Map<String, SettingsTabState> tabs;
  final bool isSaving;

  bool get anyDirty => tabs.values.any((t) => t.dirty);

  SettingsState copyWith({Map<String, SettingsTabState>? tabs, bool? isSaving}) =>
      SettingsState(tabs: tabs ?? this.tabs, isSaving: isSaving ?? this.isSaving);
}

class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  SettingsTabState tab(String key) => state.tabs[key] ?? const SettingsTabState();

  Future<void> loadAll() async {
    final api = ref.read(apiClientProvider);
    final results = await Future.wait(
      settingsTabs.map((config) => api.get('/api/lookups/${config.key}')),
    );
    final tabs = <String, SettingsTabState>{
      for (final (i, config) in settingsTabs.indexed)
        config.key: SettingsTabState(
          rows: (results[i] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          loaded: true,
        ),
    };
    state = SettingsState(tabs: tabs);
  }

  void upsertRow(String key, int? index, Map<String, dynamic> row) {
    final t = tab(key);
    final rows = [...t.rows];
    if (index == null) {
      rows.add(row);
    } else {
      rows[index] = row;
    }
    state = state.copyWith(tabs: {
      ...state.tabs,
      key: t.copyWith(rows: rows, dirty: true),
    });
  }

  void deleteRow(String key, int index) {
    final t = tab(key);
    final rows = [...t.rows];
    final removed = rows.removeAt(index);
    final deleteIds = [...t.deleteIds];
    final id = removed['id'] as int?;
    if (id != null && id > 0) deleteIds.add(id);
    state = state.copyWith(tabs: {
      ...state.tabs,
      key: t.copyWith(rows: rows, deleteIds: deleteIds, dirty: true),
    });
  }

  /// Saves every dirty tab as one batch each; reloads and refreshes the
  /// shared lookups cache afterwards (the old refresh_parameters()).
  Future<void> saveAll() async {
    final api = ref.read(apiClientProvider);
    state = state.copyWith(isSaving: true);
    try {
      for (final config in settingsTabs) {
        final t = tab(config.key);
        if (!t.dirty) continue;
        await api.post('/api/lookups/${config.key}/batch', body: {
          'rows': t.rows,
          'deleteIds': t.deleteIds,
        });
      }
      await loadAll();
      await clearLookupsCache();
      ref.invalidate(lookupsProvider);
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
