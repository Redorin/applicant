import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the notifications bell polls/shows stale-applicant alerts —
/// persisted per machine, same pattern as sidebar-collapsed and theme-mode.
class NotificationsEnabledController extends Notifier<bool> {
  static const _prefsKey = 'notifications-enabled';
  bool _disposed = false;

  @override
  bool build() {
    ref.onDispose(() => _disposed = true);
    _init();
    return true;
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    final saved = prefs.getBool(_prefsKey);
    if (saved != null && !_disposed) state = saved;
  }

  void set(bool enabled) {
    state = enabled;
    _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, state);
  }
}

final notificationsEnabledProvider =
    NotifierProvider<NotificationsEnabledController, bool>(
        NotificationsEnabledController.new);
