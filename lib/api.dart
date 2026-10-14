// Client for the GetALoad /v1 API (contract: api/openapi.json in the server repo).
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'transport.dart' if (dart.library.js_interop) 'transport_web.dart';

/// One saved server. Several can be saved; the token is per device and per server.
class Server {
  final String url; // e.g. https://203.0.113.5:8080, also the unique key
  final String token;
  final String fp; // hex SHA-256 of the certificate; empty = normal TLS verification (or plain HTTP)
  final String name;
  final String user; // who this device signed in as (empty: a server without users, signed in with a token)
  final bool owner; // the owner manages users

  const Server({
    required this.url,
    required this.token,
    this.fp = '',
    required this.name,
    this.user = '',
    this.owner = false,
  });

  Server copyWith({String? token, String? fp, String? name, String? user, bool? owner}) => Server(
    url: url,
    token: token ?? this.token,
    fp: fp ?? this.fp,
    name: name ?? this.name,
    user: user ?? this.user,
    owner: owner ?? this.owner,
  );

  Map<String, dynamic> toJson() => {'url': url, 'token': token, 'fp': fp, 'name': name, 'user': user, 'owner': owner};

  factory Server.fromJson(Map<String, dynamic> j) => Server(
    url: j['url'],
    token: j['token'],
    fp: j['fp'] ?? '',
    name: j['name'] ?? j['url'],
    user: j['user'] ?? '',
    owner: j['owner'] ?? false,
  );

  static String? normalizeUrl(String s) {
    s = s.replaceAll(RegExp(r'\s'), ''); // phone keyboards add spaces after "https://"
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

/// A file or folder on the server, or an entry inside an archive (then [archive] is the archive's path).
class FileEntry {
  final String name, path;
  final bool dir;
  final int size;
  final DateTime? modTime;
  final String? archive;

  const FileEntry({
    required this.name,
    required this.path,
    this.dir = false,
    this.size = 0,
    this.modTime,
    this.archive,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'dir': dir,
    'size': size,
    if (modTime != null) 'modTime': modTime!.toIso8601String(),
  };

  factory FileEntry.fromJson(Map<String, dynamic> j, {String? archive}) => FileEntry(
    name: j['name'],
    path: j['path'],
    dir: j['dir'] ?? false,
    size: j['size'] ?? 0,
    modTime: DateTime.tryParse(j['modTime'] ?? ''),
    archive: archive,
  );

  String get ext => name.contains('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';
  bool get isArchive =>
      !dir &&
      archive == null &&
      RegExp(r'\.(zip|7z|rar|tar|tgz|txz|tbz2|tar\.(gz|xz|bz2|zst))$').hasMatch(name.toLowerCase());
  bool get isVideo =>
      !dir && const {'mp4', 'mkv', 'webm', 'avi', 'mov', 'm4v', 'ts', 'm2ts', 'wmv', 'flv'}.contains(ext);
  bool get isAudio => !dir && const {'mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wav'}.contains(ext);

  static const textExts = {
    'txt',
    'md',
    'nfo',
    'log',
    'srt',
    'vtt',
    'ass',
    'ssa',
    'json',
    'xml',
    'csv',
    'ini',
    'conf',
    'cfg',
    'yaml',
    'yml',
    'sh',
    'py',
    'js',
    'html',
    'css',
    'toml',
    'sfv',
    'm3u',
    'cue',
  };
  static const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

  /// Opens in the built-in viewer (text, PDF, image).
  bool get viewable => !dir && (textExts.contains(ext) || imageExts.contains(ext) || ext == 'pdf');
}

class Api {
  final Server server;
  final Transport _t;

  Api(this.server) : _t = Transport(server);

  void close() => _t.close();

  Map<String, String> get _auth => {'Authorization': 'Bearer ${server.token}'};

  Uri uri(String path) => Uri.parse(server.url + path);

  Future<dynamic> call(String method, String path, [Object? body]) async {
    final headers = {..._auth, if (body != null) 'Content-Type': 'application/json'};
    final (status, text) = await _t.send(method, uri(path), headers, body == null ? null : jsonEncode(body));
    if (status >= 300) {
      var msg = 'HTTP $status';
      try {
        final e = jsonDecode(text);
        final errs = (e['errors'] as List?)?.map((x) => x['message']).join('; ');
        msg = (errs != null && errs.isNotEmpty) ? errs : (e['detail'] ?? msg);
      } catch (_) {}
      if (status == 401) {
        msg = 'This device needs to sign in to this server again.';
        unauthorized.value = server.url; // Home shows a "Sign in again" banner for this server
      }
      throw ApiError(status, msg);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  // ---- downloads (jobs) ----

  Future<List<Map<String, dynamic>>> jobs() async =>
      ((await call('GET', '/v1/jobs')) as List? ?? []).cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> add(String source) async => (await call('POST', '/v1/jobs', {'source': source}));

  /// Live progress of running jobs: one list per second (server-sent events). Ends when the connection drops.
  Stream<List<Map<String, dynamic>>> progress() async* {
    final data = StringBuffer();
    await for (final line in _t.lines(uri('/v1/events'), _auth)) {
      if (line.startsWith('data:')) {
        data.write(line.substring(5).trim());
      } else if (line.isEmpty && data.isNotEmpty) {
        final v = jsonDecode(data.toString());
        data.clear();
        if (v is List) yield v.cast<Map<String, dynamic>>();
      }
    }
  }

  // ---- files ----

  static String _q(String s) => Uri.encodeQueryComponent(s);
  static String _p(String s) => s.split('/').where((x) => x.isNotEmpty).map(Uri.encodeComponent).join('/');

  Future<List<FileEntry>> list(String path) async =>
      ((await call('GET', '/v1/fs?path=${_q(path)}')) as List? ?? []).map((e) => FileEntry.fromJson(e)).toList();

  Future<List<FileEntry>> listArchive(String archive, String dir) async =>
      ((await call('GET', '/v1/archive?path=${_q(archive)}&dir=${_q(dir)}')) as List? ?? [])
          .map((e) => FileEntry.fromJson(e, archive: archive))
          .toList();

  Future<void> mkdir(String path) => call('POST', '/v1/fs/mkdir', {'path': path});
  Future<void> move(String from, String to) => call('POST', '/v1/fs/move', {'from': from, 'to': to});
  Future<void> copy(String from, String to) => call('POST', '/v1/fs/copy', {'from': from, 'to': to});
  Future<void> delete(String path) => call('DELETE', '/v1/fs?path=${_q(path)}');
  Future<void> toDrive(String path, {bool move = false}) => call('POST', '/v1/copy', {'path': path, 'move': move});
  Future<Map<String, dynamic>> usage() async => await call('GET', '/v1/fs/usage');

  /// A link that needs no token (for players, the browser, other apps), valid for [ttl].
  /// For an archive entry the link signs the archive and names the entry.
  Future<Uri> signedUrl(FileEntry e, {Duration ttl = const Duration(hours: 6)}) async {
    final r = await call('POST', '/v1/fs/sign', {'path': e.archive ?? e.path, 'ttlSeconds': ttl.inSeconds});
    final q = (r['url'] as String).split('?').last; // exp=..&sig=.. (the server leaves the path unescaped)
    if (e.archive == null) return uri('/v1/raw/${_p(e.path)}?$q');
    return uri('/v1/archive/raw/${_p(e.archive!)}?$q&entry=${_q(e.path)}');
  }

  /// A server file (or archive entry) in memory, for the built-in viewers (text, PDF, images).
  Future<Uint8List> fileBytes(FileEntry e) async {
    final u = e.archive == null
        ? uri('/v1/raw/${_p(e.path)}')
        : uri('/v1/archive/raw/${_p(e.archive!)}?entry=${_q(e.path)}');
    final (status, b) = await _t.bytes(u, _auth);
    if (status >= 300) throw ApiError(status, 'HTTP $status');
    return Uint8List.fromList(b);
  }

  /// Downloads a server file (or archive entry) to [file] on the phone. Not available on web.
  Future<void> downloadTo(FileEntry e, String file, void Function(int, int) progress) {
    final u = e.archive == null
        ? uri('/v1/raw/${_p(e.path)}')
        : uri('/v1/archive/raw/${_p(e.archive!)}?entry=${_q(e.path)}');
    return _t.download(u, _auth, file, progress);
  }

  /// Token-free link to a download's stream (works while it is still downloading).
  Future<Uri> signedJobUrl(String id) async {
    final r = await call('POST', '/v1/jobs/$id/sign');
    return uri(r['url'] as String);
  }

  /// Bumped when files on the server change (a download finished, started or was removed, a file was moved or
  /// deleted), so Media and Files reload by themselves.
  static final filesChanged = ValueNotifier<int>(0);

  /// The server (by URL) that last rejected this device's token; null when all is well.
  static final unauthorized = ValueNotifier<String?>(null);

  static final _images = <String, Uint8List>{}; // ponytail: simple bound, an LRU if catalogs get huge

  /// An add-on poster or file, fetched by the server and passed through (the app never contacts add-ons).
  Future<Uint8List> addonFile(String url) async {
    final hit = _images[url];
    if (hit != null) return hit;
    final (status, b) = await _t.bytes(uri('/v1/addons/proxy?url=${_q(url)}'), _auth);
    if (status >= 300) throw ApiError(status, 'HTTP $status');
    if (_images.length > 300) _images.clear();
    return _images[url] = Uint8List.fromList(b);
  }

  static Future<String> probeFingerprint(String url) => Transport.probeFingerprint(url);
  static bool get canDownload => Transport.canDownload;
}

/// Links worth offering to download from the clipboard.
bool isDownloadLink(String s) {
  s = s.trim();
  if (s.contains(RegExp(r'\s'))) return false;
  if (s.startsWith('magnet:?')) return true;
  final u = Uri.tryParse(s);
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.contains('.');
}
