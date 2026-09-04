import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../auth/auth_provider.dart';

/// Fetches PDFs from the backend for the in-app preview (or, as a fallback,
/// saves to the per-user temp folder and opens the OS viewer).
class ReportRunner {
  ReportRunner(this._api);
  final ApiClient _api;

  Future<Uint8List> fetchPdf(String path, {Object? body}) async {
    final uri = Uri.parse('${_api.baseUrl}$path');
    final headers = {
      'Content-Type': 'application/json',
      if (_api.rawToken != null) 'X-Session-Token': _api.rawToken!,
    };

    final http.Response res;
    if (body != null) {
      res = await http.post(uri, headers: headers, body: _api.encode(body));
    } else {
      res = await http.get(uri, headers: headers);
    }
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, 'Report failed (${res.statusCode}).');
    }
    return res.bodyBytes;
  }

  Future<void> openPdf(String path, {Object? body}) async {
    await _saveAndLaunch(await fetchPdf(path, body: body));
  }

  Future<void> _saveAndLaunch(Uint8List bytes) async {
    final dir = Directory(
        '${Platform.environment['TEMP']}\\Applicants Information System');
    await dir.create(recursive: true);

    // Opportunistic cleanup of stale exports, as the old ReportExport did.
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 2));
      await for (final f in dir.list()) {
        if (f is File && (await f.lastModified()).isBefore(cutoff)) {
          await f.delete();
        }
      }
    } catch (_) {
      // Cleanup best-effort only.
    }

    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    final file = File('${dir.path}\\report-$stamp.pdf');
    await file.writeAsBytes(bytes);

    // Open in the OS default PDF viewer.
    await Process.start('explorer.exe', [file.path]);
  }
}

final reportRunnerProvider =
    Provider<ReportRunner>((ref) => ReportRunner(ref.read(apiClientProvider)));
