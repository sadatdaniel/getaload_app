// Web transport (the browser does TLS, so there is nothing to pin). Used for testing the UI with
// `flutter run -d chrome`; the server must list the dev origin in server.cors.
import 'dart:async';
import 'dart:convert';

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

import 'api.dart';

class Transport {
  final Server server;
  final _http = BrowserClient();

  Transport(this.server);

  void close() => _http.close();

  Future<http.StreamedResponse> _open(String method, Uri u, Map<String, String> headers, String? body) async {
    final req = http.Request(method, u)..headers.addAll(headers);
    if (body != null) req.body = body;
    try {
      return await _http.send(req).timeout(const Duration(seconds: 30));
    } on http.ClientException catch (e) {
      throw ApiError(0, 'Cannot reach ${server.url} (${e.message}). Is this origin in server.cors?');
    } on TimeoutException {
      throw ApiError(0, '${server.url} did not answer');
    }
  }

  Future<(int, String)> send(String method, Uri u, Map<String, String> headers, String? body) async {
    final resp = await _open(method, u, headers, body);
    return (resp.statusCode, await resp.stream.bytesToString());
  }

  Future<(int, List<int>)> bytes(Uri u, Map<String, String> headers) async {
    final resp = await _open('GET', u, headers, null);
    return (resp.statusCode, (await resp.stream.toBytes()).toList());
  }

  Stream<String> lines(Uri u, Map<String, String> headers) async* {
    final resp = await _open('GET', u, headers, null);
    if (resp.statusCode != 200) throw ApiError(resp.statusCode, 'HTTP ${resp.statusCode}');
    yield* resp.stream.transform(utf8.decoder).transform(const LineSplitter());
  }

  Future<void> download(Uri u, Map<String, String> headers, String file, void Function(int, int) progress) =>
      throw UnsupportedError('the browser downloads through a signed link instead');

  static Future<String> probeFingerprint(String url) async => '';

  static bool get canDownload => false;
}
