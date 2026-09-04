import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.errors = const []});
  final int statusCode;
  final String message;

  /// Aggregated field errors from a 422 validation response.
  final List<String> errors;

  @override
  String toString() => message;
}

/// Thin HTTP client for the local backend. Injects the session token
/// once sign-in succeeds; 401 responses surface as ApiException(401).
///
/// [onUnauthorized] fires once per stale-session 401 (e.g. the API service
/// restarted and forgot every token) so the app can bounce back to login
/// instead of every screen just silently failing forever — that silent
/// failure is exactly what happened before this existed: the search
/// typeahead looked "broken" when really the token was just dead.
class ApiClient {
  ApiClient({this.baseUrl = 'http://127.0.0.1:5080', this.onUnauthorized});

  final String baseUrl;
  final void Function()? onUnauthorized;
  String? _sessionToken;

  // A single reused Client instead of the http.get/post/etc top-level
  // convenience functions, which each open (and immediately close) a brand
  // new connection. Reusing one Client lets `package:http` keep the
  // underlying connection to 127.0.0.1 alive between requests instead of
  // paying fresh TCP/handshake setup on every single call — this API is hit
  // very frequently (every screen, every keystroke-debounced search, the
  // 9-endpoint lookups fan-out, master data load + photo fetch back-to-back).
  final http.Client _client = http.Client();

  // The backend's own Dapper command timeout is 90s (raised from the 30s
  // default because this runs on a machine that can starve SQL Server of
  // scheduling time) — 30s here surfaces a fast, actionable error to the
  // user well before that, instead of leaving a screen on an infinite
  // spinner if the server is ever genuinely stuck.
  static const _timeout = Duration(seconds: 30);

  set sessionToken(String? token) => _sessionToken = token;
  bool get isSignedIn => _sessionToken != null;

  /// For callers doing their own HTTP (e.g. binary PDF downloads).
  String? get rawToken => _sessionToken;
  String encode(Object body) => jsonEncode(body);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Session-Token': ?_sessionToken,
      };

  Never _onTimeout() => throw ApiException(
      408, 'The server is taking too long to respond. Try again in a moment.');

  Future<dynamic> get(String path, {Duration? timeout}) async {
    final res = await _client
        .get(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(timeout ?? _timeout, onTimeout: _onTimeout);
    return _decode(res, path);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout, onTimeout: _onTimeout);
    return _decode(res, path);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final res = await _client
        .put(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout, onTimeout: _onTimeout);
    return _decode(res, path);
  }

  Future<dynamic> delete(String path) async {
    final res = await _client
        .delete(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(_timeout, onTimeout: _onTimeout);
    return _decode(res, path);
  }

  /// Raw bytes for a binary GET (e.g. a stored photo) — no JSON decoding.
  Future<Uint8List> getBytes(String path) async {
    final res = await _client
        .get(Uri.parse('$baseUrl$path'), headers: {'X-Session-Token': ?_sessionToken})
        .timeout(_timeout, onTimeout: _onTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, 'Request failed (${res.statusCode}).');
    }
    return res.bodyBytes;
  }

  /// Multipart file upload (e.g. the applicant photo). Deliberately doesn't
  /// reuse [_headers] — that hardcodes application/json, which would break
  /// the multipart boundary `http` sets on the request itself.
  Future<dynamic> uploadPhoto(String path, Uint8List bytes, String filename) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    if (_sessionToken != null) request.headers['X-Session-Token'] = _sessionToken!;
    request.files.add(http.MultipartFile.fromBytes('photo', bytes, filename: filename));
    final streamed =
        await _client.send(request).timeout(_timeout, onTimeout: _onTimeout);
    final res = await http.Response.fromStream(streamed);
    return _decode(res, path);
  }

  dynamic _decode(http.Response res, String path) {
    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    // Login/logout return their own 401s for wrong credentials — that's not
    // a dead session, so it shouldn't trigger the bounce-to-login callback.
    if (res.statusCode == 401 && !path.startsWith('/api/auth/')) {
      onUnauthorized?.call();
    }
    final errors = switch (body) {
      {'errors': final List e} => e.cast<String>(),
      _ => const <String>[],
    };
    final message = switch (body) {
      {'error': final String e} => e,
      {'errors': final List e} => e.join('\n'),
      _ => 'Request failed (${res.statusCode}).',
    };
    throw ApiException(res.statusCode, message, errors: errors);
  }
}
