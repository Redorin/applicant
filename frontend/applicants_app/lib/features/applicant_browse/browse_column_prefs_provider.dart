import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Toggleable Browse grid columns. Applicant is never in this set — hiding
/// the one column that identifies the row would make the grid useless.
const kBrowseColumns = <String, String>{
  'municipality': 'Municipality',
  'position': 'Position applied',
  'office': 'Office',
  'dateApplied': 'Date applied',
  'status': 'Status',
  'dateHired': 'Date hired',
  'finalPosition': 'Final position',
  'finalDepartment': 'Final department',
};

/// The set of currently HIDDEN column keys — empty by default (everything
/// shown), persisted per-machine like the other view preferences.
class BrowseColumnPrefsController extends Notifier<Set<String>> {
  static const _prefsKey = 'browse-hidden-columns';
  bool _disposed = false;

  @override
  Set<String> build() {
    ref.onDispose(() => _disposed = true);
    _init();
    return const {};
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    final saved = prefs.getStringList(_prefsKey);
    if (saved != null && !_disposed) state = saved.toSet();
  }

  void toggle(String key) {
    final next = Set<String>.from(state);
    if (!next.add(key)) next.remove(key);
    state = next;
    _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state.toList());
  }
}

final browseColumnPrefsProvider =
    NotifierProvider<BrowseColumnPrefsController, Set<String>>(
        BrowseColumnPrefsController.new);
