// App settings (on this device) and remembered playback positions.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  static final instance = AppSettings();
  late SharedPreferences _p;

  Future<void> load() async => _p = await SharedPreferences.getInstance();

  int _int(String k, int d) => _p.getInt(k) ?? d;
  Future<void> _set(String k, Object v) async {
    if (v is int) await _p.setInt(k, v);
    if (v is double) await _p.setDouble(k, v);
    if (v is String) await _p.setString(k, v);
    if (v is bool) await _p.setBool(k, v);
    notifyListeners();
  }

  // ---- player ----

  /// Memory mpv may use to buffer ahead (MiB).
  int get bufferMiB => _int('bufferMiB', 64);
  set bufferMiB(int v) => _set('bufferMiB', v);

  /// How far ahead mpv reads (seconds).
  int get readaheadSecs => _int('readaheadSecs', 60);
  set readaheadSecs(int v) => _set('readaheadSecs', v);

  /// Seek buttons and double tap jump this many seconds.
  int get seekStep => _int('seekStep', 10);
  set seekStep(int v) => _set('seekStep', v);

  /// mpv hwdec: auto-safe (hardware when it is known to work), auto-copy, mediacodec, no (software).
  String get hwdec => _p.getString('hwdec') ?? 'auto-safe';
  set hwdec(String v) => _set('hwdec', v);

  double get subtitleScale => _p.getDouble('subtitleScale') ?? 1.0;
  set subtitleScale(double v) => _set('subtitleScale', v);

  /// Language codes tried first for audio and subtitles, e.g. "en,de".
  String get preferredLanguages => _p.getString('preferredLanguages') ?? '';
  set preferredLanguages(String v) => _set('preferredLanguages', v);

  // ---- look ----

  /// light (default), dark or system.
  String get theme => _p.getString('theme') ?? 'light';
  set theme(String v) => _set('theme', v);

  bool get filesGrid => _p.getBool('filesGrid') ?? true;
  set filesGrid(bool v) => _set('filesGrid', v);

  // ---- adding torrents ----

  /// Show the options dialog when torrents are added; off after "Don't ask again".
  bool get torrentAsk => _p.getBool('torrentAsk') ?? true;
  set torrentAsk(bool v) => _set('torrentAsk', v);

  Map<String, dynamic> get torrentDefaults => jsonDecode(_p.getString('torrentDefaults') ?? '{}');
  set torrentDefaults(Map<String, dynamic> v) => _set('torrentDefaults', jsonEncode(v));

  // ---- resume ----

  Duration? position(String id) {
    final ms = _p.getInt('pos:$id');
    return ms == null ? null : Duration(milliseconds: ms);
  }

  /// Remembers where playback stopped; near the end it forgets, so the next play starts over.
  Future<void> savePosition(String id, Duration pos, Duration total) async {
    if (total > Duration.zero && pos > total * 0.95 || pos < const Duration(seconds: 5)) {
      await _p.remove('pos:$id');
    } else {
      await _p.setInt('pos:$id', pos.inMilliseconds);
    }
  }

  /// Recently played items, newest first: {item: Playable JSON, pos: ms, dur: ms}. Feeds "Continue watching".
  List<Map<String, dynamic>> get recent {
    final s = _p.getString('recent');
    return s == null ? [] : (jsonDecode(s) as List).cast<Map<String, dynamic>>();
  }

  /// Moves [item] to the front with its position; finished items drop out of the list.
  Future<void> touchRecent(Map<String, dynamic> item, Duration pos, Duration dur) async {
    final l = recent.where((r) => r['item']['id'] != item['id']).toList();
    final finished = dur > Duration.zero && pos > dur * 0.95;
    if (!finished) l.insert(0, {'item': item, 'pos': pos.inMilliseconds, 'dur': dur.inMilliseconds});
    await _set('recent', jsonEncode(l.take(30).toList()));
  }
}
