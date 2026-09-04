import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Data for a toast notification, optionally with an undo action.
class ToastData {
  const ToastData(this.message, {this.onUndo});
  final String message;
  final VoidCallback? onUndo;

  bool get hasUndo => onUndo != null;
}

/// Transient bottom-right toast ("Saved", "Exported N rows", …).
/// Supports an optional undo action shown as a tappable "UNDO" label.
class ToastNotifier extends Notifier<ToastData?> {
  Timer? _timer;

  @override
  ToastData? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(String message, {Duration duration = const Duration(seconds: 3)}) {
    _timer?.cancel();
    state = ToastData(message);
    _timer = Timer(duration, () => state = null);
  }

  void showUndo(String message, VoidCallback onUndo,
      {Duration duration = const Duration(seconds: 8)}) {
    _timer?.cancel();
    state = ToastData(message, onUndo: onUndo);
    _timer = Timer(duration, () => state = null);
  }

  void dismiss() {
    _timer?.cancel();
    state = null;
  }
}

final toastProvider = NotifierProvider<ToastNotifier, ToastData?>(ToastNotifier.new);

/// How many NEW applicants were saved today. Resets when the date turns.
class EncodedTodayNotifier extends Notifier<int> {
  DateTime _day = DateTime.now();

  @override
  int build() => 0;

  void increment() {
    final now = DateTime.now();
    if (now.year != _day.year ||
        now.month != _day.month ||
        now.day != _day.day) {
      _day = now;
      state = 0;
    }
    state = state + 1;
  }
}

final encodedTodayProvider =
    NotifierProvider<EncodedTodayNotifier, int>(EncodedTodayNotifier.new);
