// Add-ons in "Ask from this phone" mode: add-ons that refuse the server (many block cloud servers) are asked by
// the app instead. The phone only fetches their JSON over HTTPS: titles, details and the list of sources. It never
// connects to torrent peers, trackers or the DHT: a chosen source goes to the server (POST /v1/addons/play), which
// does all downloading and torrenting, and the app plays the server's stream link.
import 'dart:convert';

import 'package:http/http.dart' as http;

class PhoneAddon {
  final String url; // base, without /manifest.json
  final Map<String, dynamic> manifest;
  const PhoneAddon(this.url, this.manifest);
  String get name => manifest['name'] ?? url;
}

class PhoneAddons {
  static final _manifests = <String, Map<String, dynamic>>{};

  /// GETs one add-on route (JSON only, 20 s, 8 MiB at most).
  static Future<Map<String, dynamic>> _get(String u) async {
    final uri = Uri.parse(u);
    if (uri.scheme != 'https' && uri.scheme != 'http') throw Exception('not a web address');
    final r = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('the add-on answered HTTP ${r.statusCode}');
    if (r.bodyBytes.length > 8 << 20) throw Exception('the add-on answer is too large');
    return (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>();
  }

  static Future<Map<String, dynamic>> manifest(String base) async {
    final hit = _manifests[base];
    if (hit != null) return hit;
    final m = await _get('$base/manifest.json');
    if (m['id'] == null || m['name'] == null || m['resources'] == null) {
      throw Exception('this is not a Stremio add-on manifest');
    }
    return _manifests[base] = m;
  }

  /// The enabled phone-mode add-ons from GET /v1/addons whose manifests load.
  static Future<List<PhoneAddon>> load(List<Map<String, dynamic>> infos) async {
    final out = <PhoneAddon>[];
    await Future.wait([
      for (final a in infos)
        if (a['phone'] == true && a['enabled'] != false)
          manifest(a['url']).then((m) => out.add(PhoneAddon(a['url'], m))).catchError((_) {}),
    ]);
    return out;
  }

  /// Whether the add-on answers [resource] for this type and id (same rules as the server's addons.Handles).
  static bool handles(Map<String, dynamic> m, String resource, String type, String id) {
    for (final r in (m['resources'] as List? ?? [])) {
      final isObj = r is Map;
      if ((isObj ? r['name'] : r) != resource) continue;
      var types = (m['types'] as List?)?.cast<String>() ?? [];
      var prefixes = (m['idPrefixes'] as List?)?.cast<String>() ?? [];
      if (isObj) {
        if ((r['types'] as List?)?.isNotEmpty ?? false) types = (r['types'] as List).cast<String>();
        prefixes = (r['idPrefixes'] as List?)?.cast<String>() ?? [];
      }
      if (types.isNotEmpty && !types.contains(type)) return false;
      if (resource == 'catalog' || prefixes.isEmpty) return true;
      return prefixes.any(id.startsWith);
    }
    return false;
  }

  static String _route(String base, String resource, String type, String id, [Map<String, String>? extra]) {
    var u = '$base/$resource/${Uri.encodeComponent(type)}/${Uri.encodeComponent(id)}';
    final parts = [
      for (final e in (extra ?? {}).entries)
        if (e.value.isNotEmpty) '${e.key}=${Uri.encodeQueryComponent(e.value)}',
    ];
    if (parts.isNotEmpty) u += '/${parts.join('&')}';
    return '$u.json';
  }

  static List<String> _required(Map c) => [
    ...((c['extraRequired'] as List?)?.cast<String>() ?? []),
    for (final e in (c['extra'] as List? ?? []))
      if (e is Map && e['isRequired'] == true) e['name'] as String,
  ];

  static bool _supports(Map c, String name) =>
      (c['extra'] as List? ?? []).any((e) => e is Map && e['name'] == name) ||
      ((c['extraSupported'] as List?)?.contains(name) ?? false);

  /// Catalog rows shaped like the server's /v1/addons/home and /search answers: {addon, type, id, name, metas}.
  static Future<List<Map<String, dynamic>>> catalogs(List<PhoneAddon> addons, {String query = ''}) async {
    final jobs = <Future<Map<String, dynamic>?>>[];
    for (final a in addons) {
      for (final c in (a.manifest['catalogs'] as List? ?? []).cast<Map>()) {
        final req = _required(c);
        final fits = query.isEmpty ? req.isEmpty : _supports(c, 'search') && req.every((r) => r == 'search');
        if (!fits) continue;
        jobs.add(() async {
          try {
            final r = await _get(
              _route(a.url, 'catalog', c['type'], c['id'], query.isEmpty ? null : {'search': query}),
            );
            final metas = (r['metas'] as List? ?? []);
            if (metas.isEmpty) return null;
            return {'addon': a.name, 'type': c['type'], 'id': c['id'], 'name': c['name'] ?? c['id'], 'metas': metas};
          } catch (_) {
            return null;
          }
        }());
      }
    }
    return (await Future.wait(jobs)).whereType<Map<String, dynamic>>().toList();
  }

  static Future<Map<String, dynamic>?> meta(List<PhoneAddon> addons, String type, String id) async {
    for (final a in addons.where((a) => handles(a.manifest, 'meta', type, id))) {
      try {
        final m = (await _get(_route(a.url, 'meta', type, id)))['meta'];
        if (m is Map && m['id'] != null) return m.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  /// Sources for a title, tagged with the add-on's name like the server's /v1/addons/streams answer. They are only
  /// descriptions (an info hash, a link); playing one always goes through the server.
  static Future<List<Map<String, dynamic>>> streams(List<PhoneAddon> addons, String type, String id) async {
    final lists = await Future.wait([
      for (final a in addons.where((a) => handles(a.manifest, 'stream', type, id)))
        _get(_route(a.url, 'stream', type, id))
            .then(
              (r) => [
                for (final s in (r['streams'] as List? ?? []))
                  if (s is Map) {...s.cast<String, dynamic>(), 'addon': a.name},
              ],
            )
            .catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return [for (final l in lists) ...l];
  }
}
