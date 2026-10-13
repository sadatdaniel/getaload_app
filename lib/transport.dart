// Android (dart:io) transport: HttpClient so a self-signed certificate can be pinned by its fingerprint.
// The web build uses transport_web.dart instead (the browser does TLS there).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api.dart';

/// An HttpClient that accepts a self-signed certificate only if it is the paired one (empty fp: normal TLS).
HttpClient pinnedClient(String fp) => HttpClient()
  ..connectionTimeout = const Duration(seconds: 10)
  // Called only for certificates the system does not trust (self-signed).
  ..badCertificateCallback = (cert, host, port) => fp.isNotEmpty && fingerprint(cert.der) == fp;

class Transport {
  final Server server;
  final HttpClient _http;

  Transport(this.server) : _http = pinnedClient(server.fp);

  void close() => _http.close(force: true);

  // A pinned server must present the pinned certificate even if some CA would also vouch for another one.
  void _checkPin(HttpClientResponse r) {
    final c = r.certificate;
    if (server.fp.isNotEmpty && c != null && fingerprint(c.der) != server.fp) {
      throw ApiError(0, 'The server certificate changed. Pair this server again.');
    }
  }

  Future<HttpClientResponse> _open(String method, Uri u, Map<String, String> headers, String? body) async {
    try {
      final req = await _http.openUrl(method, u);
      headers.forEach(req.headers.set);
      if (body != null) req.write(body);
      final resp = await req.close().timeout(const Duration(seconds: 30));
      _checkPin(resp);
      return resp;
    } on HandshakeException {
      throw ApiError(0, 'Certificate does not match this server. Pair it again.');
    } on SocketException catch (e) {
      throw ApiError(0, 'Cannot reach ${server.url} (${e.osError?.message ?? e.message})');
    } on TimeoutException {
      throw ApiError(0, '${server.url} did not answer');
    }
  }

  Future<(int, String)> send(String method, Uri u, Map<String, String> headers, String? body) async {
    final resp = await _open(method, u, headers, body);
    return (resp.statusCode, await resp.transform(utf8.decoder).join());
  }

  Future<(int, List<int>)> bytes(Uri u, Map<String, String> headers) async {
    final resp = await _open('GET', u, headers, null);
    final b = <int>[];
    await for (final c in resp) {
      b.addAll(c);
    }
    return (resp.statusCode, b);
  }

  Stream<String> lines(Uri u, Map<String, String> headers) async* {
    final resp = await _open('GET', u, headers, null);
    if (resp.statusCode != 200) throw ApiError(resp.statusCode, 'HTTP ${resp.statusCode}');
    yield* resp.transform(utf8.decoder).transform(const LineSplitter());
  }

  /// Saves u to [file] (a .part file first), reporting (received, total). total is -1 when unknown.
  Future<void> download(Uri u, Map<String, String> headers, String file, void Function(int, int) progress) async {
    final resp = await _open('GET', u, headers, null);
    if (resp.statusCode != 200) throw ApiError(resp.statusCode, 'HTTP ${resp.statusCode}');
    final part = File('$file.part');
    final out = part.openWrite();
    var got = 0;
    try {
      await for (final chunk in resp) {
        out.add(chunk);
        got += chunk.length;
        progress(got, resp.contentLength);
      }
      await out.close();
      await part.rename(file);
    } catch (_) {
      await out.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  /// For a server typed in by hand: the fingerprint of its certificate if the system does not trust it
  /// (self-signed), '' if it does or if it is plain HTTP. The user compares it with `dmn connect`.
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
      throw ApiError(0, 'Cannot reach $url (${e.osError?.message ?? e.message}). $_firewallHint');
    } on TimeoutException {
      throw ApiError(0, '$url did not answer. $_firewallHint');
    } finally {
      h.close(force: true);
    }
  }

  static const _firewallHint =
      'Check the address (the server\'s public IP, not 10.x or 192.168.x when you are away) and that the port is '
      'open in the server\'s firewall and, on a cloud VM, in the provider\'s console. "sudo dmn connect" on the '
      'server shows the steps.';

  static bool get canDownload => true;
}
