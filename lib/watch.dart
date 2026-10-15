// Watch progress follows the user across devices: each server file's position is one of the signed-in user's
// preferences on the server ("w_<hash>"), merged into this device's Continue watching when Media opens.
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'api.dart';
import 'media.dart';
import 'settings.dart';

class WatchSync {
  static final _sent = <String, DateTime>{};

  static String _key(Map<String, String> src) =>
      'w_${sha256.convert(utf8.encode('${src['archive'] ?? ''}:${src['path']}')).toString().substring(0, 40)}';

  /// Saves a position on the server, at most every 30 s per item unless [force] (closing the player).
  static Future<void> push(Playable item, Duration pos, Duration dur, {bool force = false}) async {
    final srv = item.via, src = item.source;
    if (srv == null || srv.user.isEmpty || src['server'] != srv.url || src['path'] == null) return;
    final k = _key(src);
    final last = _sent[k];
    if (!force && last != null && DateTime.now().difference(last) < const Duration(seconds: 30)) return;
    _sent[k] = DateTime.now();
    final api = Api(srv);
    try {
      final finished = dur > Duration.zero && pos > dur * 0.95 || pos < const Duration(seconds: 5);
      if (finished) {
        await api.call('DELETE', '/v1/prefs/$k');
      } else {
        await api.call('PUT', '/v1/prefs/$k', {
          'title': item.title,
          'path': src['path'],
          'archive': src['archive'] ?? '',
          'pos': pos.inMilliseconds,
          'dur': dur.inMilliseconds,
          'at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (_) {
      // offline or an older server: the position stays on this device
    } finally {
      api.close();
    }
  }

  /// Where the person stopped this file on any of their devices (the server keeps the newest: every device saves
  /// there, always when closing the player). Null when unknown, finished, or the server can't be reached quickly.
  static Future<Duration?> position(Playable item) async {
    final srv = item.via, src = item.source;
    if (srv == null || srv.user.isEmpty || src['server'] != srv.url || src['path'] == null) return null;
    final api = Api(srv);
    try {
      final p = (await api.call('GET', '/v1/prefs').timeout(const Duration(seconds: 3))) as Map<String, dynamic>?;
      final w = p?[_key(src)];
      return w is Map && w['pos'] is num ? Duration(milliseconds: (w['pos'] as num).toInt()) : null;
    } catch (_) {
      return null;
    } finally {
      api.close();
    }
  }

  /// Merges the user's positions from the server into this device's Continue watching.
  static Future<void> pull(Api api) async {
    if (api.server.user.isEmpty) return;
    try {
      final p = (await api.call('GET', '/v1/prefs')) as Map<String, dynamic>? ?? {};
      final watched = p.entries
          .where((e) => e.key.startsWith('w_') && e.value is Map)
          .map((e) => (e.value as Map).cast<String, dynamic>());
      await AppSettings.instance.mergeWatched(api.server.url, watched);
    } catch (_) {}
  }
}
