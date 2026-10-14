// The app updates itself from its public GitHub releases (Android): the latest release's APK for this phone's CPU
// is downloaded, checked against the release's checksums.txt, and handed to Android's installer, which only accepts
// it when it carries the same signing key as the installed app. Off in builds made with --dart-define=SELF_UPDATE=false
// (e.g. F-Droid, which updates its own builds).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Set by the release build (--dart-define=APP_VERSION=x.y.z); "dev" for local builds.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
const selfUpdate = bool.fromEnvironment('SELF_UPDATE', defaultValue: true);
const _repo = 'sadatdaniel/getaload_app';
const _channel = MethodChannel('getaload/system');

class AppRelease {
  final String version, apkName, apkUrl, sha256, notes;
  const AppRelease(this.version, this.apkName, this.apkUrl, this.sha256, this.notes);
}

/// True when [latest] is a newer x.y.z than [current] (a "dev" build is older than any release).
bool isNewer(String latest, String current) {
  List<int> parts(String v) => v.split('-').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  if (current == 'dev') return true;
  final a = parts(latest), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// The checksum of [name] in a sha256sum file (lines of `hex  name`), or "".
String checksumFor(String sums, String name) {
  for (final l in const LineSplitter().convert(sums)) {
    final f = l.trim().split(RegExp(r'\s+'));
    if (f.length == 2 && f[1].replaceFirst('*', '') == name) return f[0].toLowerCase();
  }
  return '';
}

/// The latest release with the APK for this phone, or null when there is no fitting APK.
Future<AppRelease?> latestRelease() async {
  final r = await http
      .get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      )
      .timeout(const Duration(seconds: 20));
  if (r.statusCode == 404) return null; // no release yet
  if (r.statusCode != 200) throw Exception('GitHub answered HTTP ${r.statusCode}');
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  final version = (j['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), '');
  final assets = ((j['assets'] as List?) ?? []).cast<Map<String, dynamic>>();
  final abi = await _channel.invokeMethod<String>('abi') ?? 'arm64-v8a';
  final apk = assets.where((a) => '${a['name']}'.endsWith('-$abi.apk')).firstOrNull;
  final sums = assets.where((a) => a['name'] == 'checksums.txt').firstOrNull;
  if (apk == null || sums == null) return null;
  final s = await http.get(Uri.parse(sums['browser_download_url'])).timeout(const Duration(seconds: 20));
  final hash = checksumFor(s.body, apk['name']);
  if (s.statusCode != 200 || hash.isEmpty) throw Exception('the release has no checksum for ${apk['name']}');
  return AppRelease(version, apk['name'], apk['browser_download_url'], hash, j['body'] ?? '');
}

/// Downloads the APK, checks its SHA-256, and opens Android's "update this app?" screen.
Future<void> installRelease(AppRelease rel, void Function(int done, int total) progress) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
  if (dir.existsSync()) dir.deleteSync(recursive: true); // only the newest download is kept
  dir.createSync(recursive: true);
  final file = File('${dir.path}/${rel.apkName}');
  final client = http.Client();
  try {
    final resp = await client.send(http.Request('GET', Uri.parse(rel.apkUrl)));
    if (resp.statusCode != 200) throw Exception('download failed: HTTP ${resp.statusCode}');
    final total = resp.contentLength ?? 0;
    var done = 0;
    final sink = file.openWrite();
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      done += chunk.length;
      progress(done, total);
    }
    await sink.close();
  } finally {
    client.close();
  }
  final got = (await sha256.bind(file.openRead()).first).toString();
  if (got != rel.sha256) {
    file.deleteSync();
    throw Exception('the download does not match its checksum; nothing was installed');
  }
  await _channel.invokeMethod('installApk', {'path': file.path});
}
