// Saved servers (URL, device token, certificate pin) in Android's encrypted storage.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

class Servers extends ChangeNotifier {
  static const _store = FlutterSecureStorage();
  List<Server> list = [];
  String active = ''; // url of the selected server
  String lastClip = ''; // clipboard text already offered, so it is not offered again

  Server? get current => list.where((s) => s.url == active).firstOrNull ?? list.firstOrNull;

  Future<void> load() async {
    try {
      final raw = await _store.read(key: 'servers');
      if (raw != null) list = (jsonDecode(raw) as List).map((e) => Server.fromJson(e)).toList();
      active = await _store.read(key: 'active') ?? '';
      lastClip = await _store.read(key: 'lastClip') ?? '';
    } catch (_) {
      list = []; // unreadable after a backup restore to another device: start over (tokens are per device anyway)
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await _store.write(key: 'servers', value: jsonEncode(list.map((s) => s.toJson()).toList()));
    await _store.write(key: 'active', value: active);
    notifyListeners();
  }

  /// Adds a server, or replaces the one with the same URL (pairing again gives a new token), and selects it.
  Future<void> add(Server s) async {
    final i = list.indexWhere((x) => x.url == s.url);
    if (i >= 0) {
      list[i] = Server(url: s.url, token: s.token, fp: s.fp, name: list[i].name);
    } else {
      list.add(s);
    }
    active = s.url;
    await _save();
  }

  Future<void> remove(Server s) async {
    list.removeWhere((x) => x.url == s.url);
    if (active == s.url) active = list.firstOrNull?.url ?? '';
    await _save();
  }

  Future<void> select(Server s) async {
    active = s.url;
    await _save();
  }

  Future<void> rename(Server s, String name) async {
    final i = list.indexWhere((x) => x.url == s.url);
    if (i < 0) return;
    list[i] = Server(url: s.url, token: s.token, fp: s.fp, name: name);
    await _save();
  }

  Future<void> seenClip(String text) async {
    lastClip = text;
    await _store.write(key: 'lastClip', value: text);
  }
}
