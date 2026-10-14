// Saved servers (URL, device token, certificate pin) in Android's encrypted storage.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'settings.dart';

class Servers extends ChangeNotifier {
  static const _store = FlutterSecureStorage();
  List<Server> list = [];
  String active = ''; // url of the selected server

  Server? get current => list.where((s) => s.url == active).firstOrNull ?? list.firstOrNull;

  Future<void> load() async {
    try {
      final raw = await _store.read(key: 'servers');
      if (raw != null) list = (jsonDecode(raw) as List).map((e) => Server.fromJson(e)).toList();
      active = await _store.read(key: 'active') ?? '';
      await _store.delete(key: 'lastClip'); // the old clipboard check kept the last copied link; not needed now
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

  /// Adds a server, or replaces the one with the same URL (signing in again gives a new token), and selects it.
  /// Signing in as someone else forgets what the previous user watched on this device.
  Future<void> add(Server s) async {
    final i = list.indexWhere((x) => x.url == s.url);
    if (i >= 0) {
      if (list[i].user != s.user) await AppSettings.instance.forgetServer(s.url);
      list[i] = s.copyWith(name: list[i].name);
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
    list[i] = s.copyWith(name: name);
    await _save();
  }

  /// A short random id for this install, so each device signs in under its own name ("Android 3f9a").
  Future<String> deviceName() async {
    var id = await _store.read(key: 'deviceId');
    if (id == null) {
      id = (Random.secure().nextInt(0xffff) + 0x10000).toRadixString(16).substring(1);
      await _store.write(key: 'deviceId', value: id);
    }
    final p = defaultTargetPlatform.name;
    return '${kIsWeb ? 'Browser' : p[0].toUpperCase() + p.substring(1)} $id';
  }
}
