// Client for the download_me_not /v1 API (contract: api/openapi.json in the server repo).
// dart:io HttpClient so a self-signed certificate can be pinned by its SHA-256 fingerprint.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// One paired server. Several can be saved; the token is per device and per server.
class Server {
  final String url; // e.g. https://203.0.113.5:8080, also the unique key
  final String token;
  final String fp; // hex SHA-256 of the certificate; empty = normal TLS verification (or plain HTTP)
  final String name;

  const Server({required this.url, required this.token, this.fp = '', required this.name});

  Map<String, dynamic> toJson() => {'url': url, 'token': token, 'fp': fp, 'name': name};

  factory Server.fromJson(Map<String, dynamic> j) =>
      Server(url: j['url'], token: j['token'], fp: j['fp'] ?? '', name: j['name'] ?? j['url']);

  /// Parses the dmn://pair?v=1&url=..&token=..&fp=.. link from `dmn pair` or the web panel.
  static Server? fromPairLink(String link) {
    final u = Uri.tryParse(link.trim());
    if (u == null || u.scheme != 'dmn' || u.host != 'pair') return null;
    final q = u.queryParameters;
    final url = normalizeUrl(q['url'] ?? '');
    final token = q['token'] ?? '';
    if (url == null || token.isEmpty) return null;
    return Server(url: url, token: token, fp: (q['fp'] ?? '').toLowerCase(), name: Uri.parse(url).host);
  }

  static String? normalizeUrl(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) return null;
    return '${u.scheme}://${u.authority}';
  }
}

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
  @override
  String toString() => message;
}

String fingerprint(List<int> der) => sha256.convert(der).toString();

class Api {
  final Server server;
  final HttpClient _http;

  Api(this.server) : _http = _client(server.fp);

  static HttpClient _client(String fp) => HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    // Called only for certificates the system does not trust (self-signed): accept exactly the paired one.
    ..badCertificateCallback = (cert, host, port) => fp.isNotEmpty && fingerprint(cert.der) == fp;

  void close() => _http.close(force: true);

  Uri _uri(String path) => Uri.parse(server.url + path);

  // A pinned server must present the pinned certificate even if some CA would also vouch for another one.
  void _checkPin(HttpClientResponse r) {
    final c = r.certificate;
    if (server.fp.isNotEmpty && c != null && fingerprint(c.der) != server.fp) {
      throw ApiError(0, 'The server certificate changed. Pair this server again.');
    }
  }

  Future<dynamic> call(String method, String path, [Object? body]) async {
    try {
      final req = await _http.openUrl(method, _uri(path));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${server.token}');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final resp = await req.close().timeout(const Duration(seconds: 30));
      _checkPin(resp);
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 300) {
        var msg = 'HTTP ${resp.statusCode}';
        try {
          final e = jsonDecode(text);
          final errs = (e['errors'] as List?)?.map((x) => x['message']).join('; ');
          msg = (errs != null && errs.isNotEmpty) ? errs : (e['detail'] ?? msg);
        } catch (_) {}
        if (resp.statusCode == 401) msg = 'This server no longer accepts the token. Pair it again.';
        throw ApiError(resp.statusCode, msg);
      }
      return text.isEmpty ? null : jsonDecode(text);
    } on HandshakeException {
      throw ApiError(0, 'Certificate does not match this server. Pair it again.');
    } on SocketException catch (e) {
      throw ApiError(0, 'Cannot reach ${server.url} (${e.osError?.message ?? e.message})');
    } on TimeoutException {
      throw ApiError(0, '${server.url} did not answer');
    }
  }

  Future<List<Map<String, dynamic>>> jobs() async =>
      ((await call('GET', '/v1/jobs')) as List? ?? []).cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> add(String source) async => (await call('POST', '/v1/jobs', {'source': source}));

  /// Live progress of running jobs: one list per second (server-sent events). Ends when the connection drops.
  Stream<List<Map<String, dynamic>>> progress() async* {
    final req = await _http.getUrl(_uri('/v1/events'));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${server.token}');
    final resp = await req.close();
    _checkPin(resp);
    if (resp.statusCode != 200) throw ApiError(resp.statusCode, 'events: HTTP ${resp.statusCode}');
    final data = StringBuffer();
    await for (final line in resp.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('data:')) {
        data.write(line.substring(5).trim());
      } else if (line.isEmpty && data.isNotEmpty) {
        final v = jsonDecode(data.toString());
        data.clear();
        if (v is List) yield v.cast<Map<String, dynamic>>();
      }
    }
  }

  /// For a server typed in by hand: the fingerprint of its certificate if the system does not trust it
  /// (self-signed), '' if it does or if it is plain HTTP. The user compares it with `dmn pair`.
  static Future<String> probeFingerprint(String url) async {
    var fp = '';
    final h = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = (cert, host, port) {
        fp = fingerprint(cert.der);
        return true; // only for this one unauthenticated /v1/health call
      };
    try {
      final resp = await (await h.getUrl(Uri.parse('$url/v1/health'))).close().timeout(const Duration(seconds: 15));
      await resp.drain();
      return fp;
    } on SocketException catch (e) {
      throw ApiError(0, 'Cannot reach $url (${e.osError?.message ?? e.message})');
    } on TimeoutException {
      throw ApiError(0, '$url did not answer');
    } finally {
      h.close(force: true);
    }
  }
}

/// Links worth offering to download from the clipboard.
bool isDownloadLink(String s) {
  s = s.trim();
  if (s.contains(RegExp(r'\s'))) return false;
  if (s.startsWith('magnet:?')) return true;
  final u = Uri.tryParse(s);
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.contains('.');
}
