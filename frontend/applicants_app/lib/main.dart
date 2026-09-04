import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

const _sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
const _apiHealthUrl = 'http://127.0.0.1:5080/health';

/// Persists window bounds so the app reopens where the user left it.
class _WindowMemory with WindowListener {
  static const _key = 'window-bounds';
  Timer? _debounce;

  void dispose() {
    _debounce?.cancel();
    windowManager.removeListener(this);
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_key);
    if (saved != null && saved.length == 4) {
      final values = saved.map(double.tryParse).toList();
      if (!values.contains(null)) {
        final bounds = Rect.fromLTWH(
            values[0]!, values[1]!, values[2]!, values[3]!);
        // Only restore when the saved area is still on a visible display
        // (e.g. a disconnected second monitor should not strand the window).
        if (bounds.width >= 400 && bounds.height >= 300) {
          await windowManager.setBounds(bounds);
        }
      }
    }
  }

  Future<void> _save() async {
    final bounds = await windowManager.getBounds();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [
      '${bounds.left}',
      '${bounds.top}',
      '${bounds.width}',
      '${bounds.height}',
    ]);
  }

  void _debouncedSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  @override
  void onWindowMoved() => _debouncedSave();

  @override
  void onWindowResized() => _debouncedSave();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await _ensureApiRunning();

  final memory = _WindowMemory();
  const windowOptions = WindowOptions(minimumSize: Size(1100, 700));
  unawaited(windowManager.waitUntilReadyToShow(windowOptions, () async {
    await memory.restore();
    await windowManager.show();
    await windowManager.focus();
  }));
  windowManager.addListener(memory);

  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      options.tracesSampleRate = 1.0;
    },
    appRunner: () =>
        runApp(const ProviderScope(child: ApplicantsApp())),
  );
}

/// Checks if the backend API is reachable; if not, starts it from the
/// sibling `api/` directory and waits for it to become healthy.
/// The API process is detached so it keeps running after the app closes.
Future<void> _ensureApiRunning() async {
  if (await _isApiHealthy()) return;

  // The exe doesn't read appsettings.json correctly — use dotnet + DLL.
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final apiDll = '$exeDir${Platform.pathSeparator}..${Platform.pathSeparator}api${Platform.pathSeparator}ApplicantsApi.dll';
  final dllFile = File(apiDll);
  if (!dllFile.existsSync()) return;

  try {
    await Process.start(
      'dotnet',
      [dllFile.path],
      workingDirectory: dllFile.parent.path,
      mode: ProcessStartMode.detached,
    );
  } catch (_) {
    return;
  }

  // Wait up to 30 seconds for the API to become healthy.
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!(await _isApiHealthy())) {
    if (DateTime.now().isAfter(deadline)) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

Future<bool> _isApiHealthy() async {
  try {
    final res = await http.get(Uri.parse(_apiHealthUrl))
        .timeout(const Duration(seconds: 2));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}
