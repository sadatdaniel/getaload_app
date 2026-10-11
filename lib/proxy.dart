// Loopback proxy for playback. mpv and other apps cannot pin our self-signed certificate (and it does not
// name the server's public IP anyway), so they play http://127.0.0.1:<port>/<secret> and this proxy fetches
// the real URL over the pinned connection, passing Range through so seeking works.
// The secret path keeps other apps on the phone from using the proxy unless we hand them a link ("open with").
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'api.dart';
import 'transport.dart' show pinnedClient;

class LocalProxy {
  static final instance = LocalProxy();
  HttpServer? _server;
  final _routes = <String, (Uri, HttpClient, String)>{}; // secret → target, client, pinned fp
  final _clients = <String, HttpClient>{};

  /// A URL a player can open for [url]. Only links to a pinned (self-signed) server need the proxy.
  Future<String> wrap(String url, Server? via) async {
    if (via == null || via.fp.isEmpty || !url.startsWith('https://')) return url;
    final s = _server ??= await _start();
    final b = List<int>.generate(18, (_) => Random.secure().nextInt(256));
    final key = base64Url.encode(b);
    _routes[key] = (Uri.parse(url), _clients[via.fp] ??= pinnedClient(via.fp), via.fp);
    // Keep the file name at the end so players can guess the format.
    final name = Uri.parse(url).pathSegments.lastOrNull ?? 'media';
    return 'http://127.0.0.1:${s.port}/$key/${Uri.encodeComponent(Uri.decodeComponent(name))}';
  }

  Future<HttpServer> _start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen(_serve);
    return s;
  }

  static const _pass = [
    'content-type',
    'content-range',
    'accept-ranges',
    'last-modified',
    'etag',
    'content-disposition',
  ];

  Future<void> _serve(HttpRequest req) async {
    final r = _routes[req.uri.pathSegments.firstOrNull];
    final out = req.response;
    if (r == null || (req.method != 'GET' && req.method != 'HEAD')) {
      out.statusCode = HttpStatus.notFound;
      await out.close();
      return;
    }
    final (target, client, fp) = r;
    try {
      final up = await client.openUrl(req.method, target);
      for (final h in ['range', 'if-range']) {
        final v = req.headers.value(h);
        if (v != null) up.headers.set(h, v);
      }
      final resp = await up.close();
      final c = resp.certificate;
      if (c != null && fingerprint(c.der) != fp) throw const HandshakeException('certificate changed');
      out.statusCode = resp.statusCode;
      for (final h in _pass) {
        final v = resp.headers.value(h);
        if (v != null) out.headers.set(h, v);
      }
      if (resp.contentLength >= 0) out.contentLength = resp.contentLength;
      await resp.pipe(out);
    } catch (_) {
      // The player sees a failed request and reports it; nothing else to do here.
      try {
        out.statusCode = HttpStatus.badGateway;
        await out.close();
      } catch (_) {}
    }
  }
}
