// What the player plays, independent of where it comes from: a server file, a file on the phone, or
// later a stream from a plugin (Stremio-style addons). New sources only have to build a Playable.
import 'api.dart';

class SubtitleSource {
  final String url, title, language;
  const SubtitleSource(this.url, {this.title = '', this.language = ''});
  Map<String, dynamic> toJson() => {'url': url, 'title': title, 'language': language};
  factory SubtitleSource.fromJson(Map<String, dynamic> j) =>
      SubtitleSource(j['url'], title: j['title'] ?? '', language: j['language'] ?? '');
}

class Playable {
  /// Stable key for the resume position, e.g. "server:https://x:8080:/Movies/a.mkv" or "file:/path".
  final String id;
  final String title;

  /// http(s), file:// or anything mpv opens.
  final String url;

  /// Extra request headers (cookies, referer) some sources need.
  final Map<String, String> headers;

  /// Fetch through this server's pinned connection (the local proxy) instead of directly.
  final Server? via;
  final List<SubtitleSource> subtitles;

  /// Where it came from, to rebuild it later (signed links expire), e.g. {server: url, path: /a.mkv, archive: ""}.
  final Map<String, String> source;

  const Playable({
    required this.id,
    required this.title,
    required this.url,
    this.headers = const {},
    this.via,
    this.subtitles = const [],
    this.source = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'headers': headers,
    'via': via?.url,
    'subtitles': subtitles.map((s) => s.toJson()).toList(),
    'source': source,
  };

  /// [servers] resolves `via` back to a saved server; signed links expire, so callers re-sign server files.
  factory Playable.fromJson(Map<String, dynamic> j, List<Server> servers) => Playable(
    id: j['id'],
    title: j['title'],
    url: j['url'],
    headers: (j['headers'] as Map? ?? {}).cast<String, String>(),
    via: servers.where((s) => s.url == j['via']).firstOrNull,
    subtitles: [for (final s in (j['subtitles'] as List? ?? [])) SubtitleSource.fromJson(s)],
    source: (j['source'] as Map? ?? {}).cast<String, String>(),
  );
}

const subtitleExts = {'srt', 'vtt', 'ass', 'ssa', 'sub'};

/// A server file as a Playable, with subtitle files of the same name in the same folder attached.
Future<Playable> serverPlayable(Api api, FileEntry e, List<FileEntry> siblings) async {
  final base = e.name.contains('.') ? e.name.substring(0, e.name.lastIndexOf('.')) : e.name;
  final subs = <SubtitleSource>[];
  for (final s in siblings) {
    if (s.dir || !subtitleExts.contains(s.ext) || !s.name.startsWith(base)) continue;
    // "Movie.en.srt" → language "en"
    final mid = s.name.substring(base.length, s.name.length - s.ext.length - 1).replaceAll('.', '');
    subs.add(SubtitleSource((await api.signedUrl(s)).toString(), title: s.name, language: mid));
  }
  return Playable(
    id: 'server:${api.server.url}:${e.archive ?? ''}:${e.path}',
    title: e.name,
    url: (await api.signedUrl(e)).toString(),
    via: api.server,
    subtitles: subs,
    source: {'server': api.server.url, 'path': e.path, 'archive': e.archive ?? ''},
  );
}

/// The other media of the same folder, for previous/next and "play the next file". Items are built on demand
/// (signed links expire), so a long folder costs nothing until it is played.
class Playlist {
  final int length;
  final int index;
  final Future<Playable> Function(int i) open;
  const Playlist({required this.length, required this.index, required this.open});
}
