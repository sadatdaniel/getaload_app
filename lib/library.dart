// Media: everything playable on the server in one list (newest first), with "Continue watching" on top.
import 'package:flutter/material.dart';

import 'api.dart';
import 'jobs.dart' show fmtBytes;
import 'media.dart';
import 'launch.dart';
import 'servers.dart';
import 'settings.dart';

class MediaView extends StatefulWidget {
  final Servers servers;
  final Server server;
  const MediaView({super.key, required this.servers, required this.server});
  @override
  State<MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends State<MediaView> {
  static final _cache = <String, List<FileEntry>>{}; // per server: shown at once, refreshed in the background
  late final Api _api = Api(widget.server);
  List<FileEntry>? _items;
  String _error = '', _query = '';
  final _s = AppSettings.instance;

  @override
  void initState() {
    super.initState();
    _items = _cache[widget.server.url];
    _load();
    _s.addListener(_changed);
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    _api.close();
    super.dispose();
  }

  void _changed() => mounted ? setState(() {}) : null;

  Future<void> _load() async {
    try {
      final l = ((await _api.call('GET', '/v1/media?limit=5000')) as List? ?? [])
          .map((e) => FileEntry.fromJson(e))
          .toList();
      _cache[widget.server.url] = l;
      if (mounted) {
        setState(() {
          _items = l;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _parent(String p) => p.lastIndexOf('/') <= 0 ? '/' : p.substring(0, p.lastIndexOf('/'));

  Future<void> _play(FileEntry e) async {
    try {
      // The folder listing finds subtitle files next to the video and the rest of the folder for previous/next.
      final siblings = e.archive == null ? await _api.list(_parent(e.path)) : <FileEntry>[];
      siblings.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final media = siblings.where((f) => f.isVideo || f.isAudio).toList();
      final i = media.indexWhere((f) => f.path == e.path);
      final p = await serverPlayable(_api, e, siblings);
      if (!mounted) return;
      await play(
        context,
        p,
        list: i < 0
            ? null
            : Playlist(length: media.length, index: i, open: (n) => serverPlayable(_api, media[n], siblings)),
      );
    } catch (x) {
      _toast(x.toString());
    }
  }

  // Signed links expire, so a server item is rebuilt from its source before playing again.
  Future<void> _resume(Map<String, dynamic> r) async {
    final p = Playable.fromJson(r['item'], widget.servers.list);
    final src = p.source;
    if (src['server'] == null) return play(context, p);
    final srv = widget.servers.list.where((s) => s.url == src['server']).firstOrNull;
    if (srv == null) return _toast('That server was removed from this phone.');
    final archive = (src['archive'] ?? '').isEmpty ? null : src['archive'];
    final e = FileEntry(name: p.title, path: src['path']!, archive: archive);
    if (srv.url == widget.server.url) return _play(e);
    final api = Api(srv);
    try {
      final siblings = archive == null ? await api.list(_parent(e.path)) : <FileEntry>[];
      final fresh = await serverPlayable(api, e, siblings);
      if (mounted) await play(context, fresh);
    } catch (x) {
      _toast(x.toString());
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final recent = _s.recent;
    final items = (_items ?? []).where((e) => _query.isEmpty || e.path.toLowerCase().contains(_query)).toList();
    final page = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (recent.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Continue watching', style: Theme.of(context).textTheme.titleMedium),
            ),
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: recent.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final r = recent[i];
                  final dur = (r['dur'] as int?) ?? 0, pos = (r['pos'] as int?) ?? 0;
                  return SizedBox(
                    width: 200,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        onTap: () => _resume(r),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.play_circle_outline),
                              const Spacer(),
                              Text(r['item']['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: dur > 0 ? pos / dur : 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search media',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(28))),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          if (_items == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(_error)),
          if (_items != null && items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No videos or music on this server yet.')),
            ),
          for (final e in items)
            ListTile(
              leading: Icon(e.isAudio ? Icons.music_note_outlined : Icons.movie_outlined),
              title: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${_parent(e.path)} · ${fmtBytes(e.size)}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: _s.position('server:${widget.server.url}::${e.path}') != null
                  ? const Icon(Icons.timelapse, size: 18)
                  : null,
              onTap: () => _play(e),
            ),
        ],
      ),
    );
    if (recent.isEmpty) return page;
    final last = recent.first;
    return Stack(
      children: [
        page,
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _resume(last),
            icon: const Icon(Icons.play_arrow),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text('Continue: ${last['item']['title'] ?? ''}', overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ],
    );
  }
}
