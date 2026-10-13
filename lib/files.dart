// File manager for one server: browse folders and archives, rename, move, copy, delete, copy to Drive,
// download to the phone, share a link.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'icons.dart';
import 'jobs.dart' show fmtBytes;
import 'media.dart';
import 'phone.dart';
import 'launch.dart';
import 'settings.dart';
import 'ui.dart';
import 'viewer.dart' deferred as viewer;

class FilesView extends StatefulWidget {
  final Server server;
  const FilesView({super.key, required this.server});
  @override
  State<FilesView> createState() => _FilesViewState();
}

/// Where the view is: a server folder, or a folder inside an archive.
class _Place {
  final String path; // server path, or the folder inside the archive ('.' = its root)
  final String? archive;
  const _Place(this.path, [this.archive]);
}

class _FilesViewState extends State<FilesView> {
  // Last listing per server and place: shown at once, then refreshed in the background, so browsing
  // never waits for the network. Lives as long as the app process.
  static final _cache = <String, List<FileEntry>>{};
  late final Api _api = Api(widget.server);
  final _stack = <_Place>[const _Place('/')];
  List<FileEntry>? _entries;
  String _error = '';
  String _free = '';

  _Place get _here => _stack.last;

  @override
  void initState() {
    super.initState();
    _load();
    Api.filesChanged.addListener(_load); // downloads finishing, files changed elsewhere
  }

  @override
  void dispose() {
    Api.filesChanged.removeListener(_load);
    _api.close();
    super.dispose();
  }

  String _key(_Place p) => '${widget.server.url}|${p.archive}|${p.path}';

  Future<void> _load() async {
    final h = _here;
    setState(() {
      _error = '';
      _entries = _cache[_key(h)] ?? _entries;
    });
    try {
      final es = h.archive == null ? await _api.list(h.path) : await _api.listArchive(h.archive!, h.path);
      es.sort((a, b) => a.dir != b.dir ? (a.dir ? -1 : 1) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _cache[_key(h)] = es;
      if (!mounted || _here != h) return; // the user moved on meanwhile
      setState(() => _entries = es);
      _loadStatus();
      _api.usage().then(
        (u) => mounted ? setState(() => _free = '${fmtBytes(u['free'] ?? 0)} free') : null,
        onError: (_) {},
      );
    } catch (e) {
      if (mounted && _here == h) {
        setState(() {
          _entries ??= [];
          _error = e.toString();
        });
      }
    }
  }

  void _go(_Place p) {
    _stack.add(p);
    _entries = null;
    _load();
  }

  bool _up() {
    if (_stack.length == 1) return false;
    _stack.removeLast();
    _entries = null;
    _load();
    return true;
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _act(Future<void> Function() f, String ok) async {
    try {
      await f();
      _toast(ok);
      Api.filesChanged.value++; // also reloads this folder
    } catch (e) {
      _toast(e.toString());
    }
  }

  String _join(String dir, String name) => dir == '/' ? '/$name' : '$dir/$name';
  String _parent(String p) => p.lastIndexOf('/') <= 0 ? '/' : p.substring(0, p.lastIndexOf('/'));

  void _open(FileEntry e) {
    if (e.dir) return _go(_Place(e.path, e.archive));
    if (e.isArchive) return _go(_Place('.', e.path));
    if (e.viewable) {
      _view(e);
      return;
    }
    if (e.isVideo || e.isAudio) {
      _play(e);
      return;
    }
    _menu(e);
  }

  // A file still downloading is played through the job stream: it waits for missing bytes and, for torrents,
  // fetches the pieces under the playhead first. Reading the file from disk would hit unwritten parts.
  Future<Playable?> _livePlayable(FileEntry e) async {
    if (e.archive != null) return null;
    String? id, rel;
    for (final MapEntry(:key, :value) in _status.entries) {
      if (value.jobId == null || value.progress == null) continue;
      if (e.path == key) id = value.jobId;
      if (e.path.startsWith('$key/')) (id, rel) = (value.jobId, e.path.substring(key.length + 1));
    }
    if (id == null) return null;
    var url = (await _api.signedJobUrl(id)).toString();
    if (rel != null) {
      // A file inside a torrent folder: the stream endpoint picks files by index.
      final files = ((await _api.call('GET', '/v1/jobs/$id/files')) as List? ?? []).cast<Map<String, dynamic>>();
      final i = files.indexWhere((f) => (f['path'] as String? ?? '').endsWith(rel!)); // the index is the list position
      if (i < 0) return null;
      url += '&file=$i';
    }
    return Playable(id: 'server:${_api.server.url}::${e.path}', title: e.name, url: url, via: _api.server);
  }

  Future<void> _play(FileEntry e) async {
    try {
      final entries = _entries ?? [];
      Future<Playable> build(FileEntry f) async =>
          await _livePlayable(f) ?? await serverPlayable(_api, f, f.archive == null ? entries : []);
      // The rest of the folder (same order as shown) becomes the playlist for previous/next.
      final media = entries.where((f) => f.isVideo || f.isAudio).toList();
      final i = media.indexWhere((f) => f.path == e.path);
      final p = await build(e);
      if (!mounted) return;
      await play(
        context,
        p,
        list: i < 0 ? null : Playlist(length: media.length, index: i, open: (n) => build(media[n])),
      );
    } catch (x) {
      _toast(x.toString());
    }
  }

  Future<void> _view(FileEntry e) async {
    await viewer.loadLibrary();
    if (mounted) await viewer.openViewer(context, _api, e);
  }

  Future<String?> _ask(String title, String initial, String action) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: Text(action)),
        ],
      ),
    );
  }

  Future<void> _download(FileEntry e) async {
    if (!Api.canDownload) {
      // Web: the browser downloads through a signed link.
      final u = await _api.signedUrl(e);
      await launchUrl(u, webOnlyWindowName: '_blank');
      return;
    }
    PhoneDownloads.instance.start(_api.server, e);
    _toast('Downloading ${e.name} to this phone');
  }

  // Where the pointer last went down, so a menu opened by a plain tap appears there.
  Offset _lastTap = Offset.zero;

  // Desktop-style context menu: right click, long press, the ⋮ button, or a tap on a file nothing else opens.
  void _menu(FileEntry e, [Offset? at]) {
    final inArchive = e.archive != null;
    void go(String a) => _do(e, a);
    showContextMenu(context, at ?? _lastTap, title: e.name, [
      if (e.dir) MenuAction('Open', icon: Icons.folder_open, onTap: () => _open(e)),
      if (e.isArchive) MenuAction('Show contents', icon: Icons.folder_zip_outlined, onTap: () => go('open')),
      if (e.isVideo || e.isAudio) MenuAction('Play', icon: Icons.play_arrow, onTap: () => go('play')),
      if (e.viewable) MenuAction('Open', icon: Icons.open_in_new, onTap: () => _view(e)),
      if (!e.dir)
        MenuAction(
          Api.canDownload ? 'Download to this phone' : 'Download',
          icon: Icons.download,
          onTap: () => go('download'),
        ),
      if (e.isVideo || e.isAudio) MenuAction('Copy stream link', icon: Icons.link, onTap: () => go('link')),
      if (!inArchive) ...[
        const MenuAction.divider(),
        MenuAction('Rename…', icon: Icons.edit_outlined, onTap: () => go('rename')),
        MenuAction('Move to…', icon: Icons.drive_file_move_outlined, onTap: () => go('move')),
        MenuAction('Copy to…', icon: Icons.copy, onTap: () => go('copy')),
        MenuAction('Copy to Google Drive', icon: Icons.add_to_drive, onTap: () => go('drive')),
        const MenuAction.divider(),
        MenuAction('Delete', icon: Icons.delete_outline, danger: true, onTap: () => go('delete')),
      ],
    ]);
  }

  Future<void> _do(FileEntry e, String a) async {
    switch (a) {
      case 'open':
        _open(e);
      case 'play':
        await _play(e);
      case 'download':
        await _download(e);
      case 'link':
        try {
          await Clipboard.setData(ClipboardData(text: (await _api.signedUrl(e)).toString()));
          _toast('Link copied; it works without a token for 6 hours');
        } catch (x) {
          _toast(x.toString());
        }
      case 'rename':
        final n = await _ask('Rename', e.name, 'Rename');
        if (n != null && n.isNotEmpty && n != e.name) {
          await _act(() => _api.move(e.path, _join(_parent(e.path), n)), 'Renamed');
        }
      case 'move' || 'copy':
        if (!mounted) return;
        final dest = await pickFolder(context, _api, a == 'move' ? 'Move here' : 'Copy here');
        if (dest != null) {
          final to = _join(dest, e.name);
          await _act(
            () => a == 'move' ? _api.move(e.path, to) : _api.copy(e.path, to),
            a == 'move' ? 'Moved' : 'Copied',
          );
        }
      case 'drive':
        await _act(() => _api.toDrive(e.path), 'Copy to Drive queued (see Downloads)');
      case 'delete':
        if (!mounted) return;
        final ok = await confirm(
          context,
          title: 'Delete ${e.name}?',
          body: Text(
            e.dir ? 'The folder and everything in it is deleted on the server.' : 'The file is deleted on the server.',
          ),
          action: 'Delete',
          danger: true,
        );
        if (ok) await _act(() => _api.delete(e.path), 'Deleted');
    }
  }

  // Badges from the job list: still downloading, or copied to a cloud. Keyed by server path.
  Map<String, FileStatus> _status = {};

  Future<void> _loadStatus() async {
    try {
      final st = <String, FileStatus>{};
      for (final j in await _api.jobs()) {
        final p = (j['path'] as String?) ?? '';
        if (p.isEmpty) continue;
        final key = '/$p';
        final prev = st[key];
        if (j['kind'] == 'copy') {
          if (j['state'] == 'done') st[key] = FileStatus(progress: prev?.progress, cloud: true, jobId: prev?.jobId);
        } else if (j['state'] != 'done' && j['state'] != 'seeding') {
          final done = (j['done'] as num?) ?? 0, total = (j['total'] as num?) ?? 0;
          st[key] = FileStatus(progress: total > 0 ? done / total : -1, cloud: prev?.cloud ?? false, jobId: j['id']);
        }
      }
      if (mounted) setState(() => _status = st);
    } catch (_) {} // badges are a nicety; the listing still works without them
  }

  Widget _crumbs(_Place h) {
    final parts = <(String, int)>[];
    for (var i = 0; i < _stack.length; i++) {
      final p = _stack[i];
      final label = i == 0
          ? 'Home'
          : p.archive != null && p.path == '.'
          ? p.archive!.split('/').last
          : p.path.split('/').last;
      parts.add((label, i));
    }
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (label, i) in parts) ...[
            if (i > 0) Icon(Icons.chevron_right, size: 18, color: cs.outline),
            ActionChip(
              label: Text(label),
              avatar: i == 0 ? const Icon(Icons.home_outlined, size: 18) : null,
              backgroundColor: i == parts.length - 1 ? cs.secondaryContainer : null,
              side: BorderSide.none,
              onPressed: i == parts.length - 1
                  ? null
                  : () {
                      _stack.removeRange(i + 1, _stack.length);
                      _entries = null;
                      _load();
                    },
            ),
          ],
        ],
      ),
    );
  }

  Widget _gridTile(FileEntry e) => ContextMenuArea(
    onMenu: (at) => _menu(e, at),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTapDown: (d) => _lastTap = d.globalPosition,
      onTap: () => _open(e),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
        child: Column(
          children: [
            EntryIcon(entry: e, size: 64, status: _status[e.path]),
            const SizedBox(height: 6),
            Text(
              e.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _listTile(FileEntry e) => ContextMenuArea(
    onMenu: (at) => _menu(e, at),
    child: InkWell(
      onTapDown: (d) => _lastTap = d.globalPosition,
      onTap: () => _open(e),
      child: ListTile(
        leading: EntryIcon(entry: e, size: 40, status: _status[e.path]),
        title: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: e.dir ? null : Text(fmtBytes(e.size)),
        trailing: Builder(
          builder: (b) =>
              IconButton(icon: const Icon(Icons.more_vert), tooltip: 'Actions', onPressed: () => _menu(e, anchorOf(b))),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final h = _here;
    final s = AppSettings.instance;
    final es = _entries;
    final note = _error.isNotEmpty && (es?.isNotEmpty ?? false)
        ? 'Showing the saved list: $_error'
        : h.archive != null
        ? 'Inside an archive (read-only)'
        : _free;
    final Widget body;
    if (es == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (es.isEmpty) {
      body = ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              children: [
                Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(height: 12),
                Text(_error.isNotEmpty ? _error : 'This folder is empty', textAlign: TextAlign.center),
              ],
            ),
          ),
        ],
      );
    } else if (s.filesGrid) {
      body = GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 116,
          mainAxisExtent: 124,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: es.length,
        itemBuilder: (_, i) => _gridTile(es[i]),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: es.length,
        itemBuilder: (_, i) => _listTile(es[i]),
      );
    }
    return PopScope(
      canPop: _stack.length == 1,
      onPopInvokedWithResult: (didPop, _) => didPop ? null : _up(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                Expanded(child: _crumbs(h)),
                if (h.archive == null)
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: 'New folder',
                    onPressed: () async {
                      final n = await _ask('New folder', '', 'Create');
                      if (n != null && n.isNotEmpty) await _act(() => _api.mkdir(_join(h.path, n)), 'Created');
                    },
                  ),
                IconButton(
                  icon: Icon(s.filesGrid ? Icons.view_list_outlined : Icons.grid_view),
                  tooltip: s.filesGrid ? 'List view' : 'Grid view',
                  onPressed: () => setState(() => s.filesGrid = !s.filesGrid),
                ),
              ],
            ),
          ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(note, style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
          Expanded(
            child: RefreshIndicator(onRefresh: _load, child: body),
          ),
        ],
      ),
    );
  }
}

/// Lets the user pick a server folder (for move and copy). Returns its path, or null.
Future<String?> pickFolder(BuildContext context, Api api, String action) {
  var dir = '/';
  return showDialog<String>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(dir),
        content: SizedBox(
          width: 400,
          height: 360,
          child: FutureBuilder<List<FileEntry>>(
            key: ValueKey(dir),
            future: api.list(dir),
            builder: (_, snap) {
              if (!snap.hasData) {
                return Center(child: snap.hasError ? Text('${snap.error}') : const CircularProgressIndicator());
              }
              final dirs = snap.data!.where((e) => e.dir).toList();
              return ListView(
                children: [
                  if (dir != '/')
                    ListTile(
                      leading: const Icon(Icons.arrow_upward),
                      title: const Text('..'),
                      onTap: () =>
                          set(() => dir = dir.lastIndexOf('/') <= 0 ? '/' : dir.substring(0, dir.lastIndexOf('/'))),
                    ),
                  for (final e in dirs)
                    ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(e.name),
                      onTap: () => set(() => dir = e.path),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, dir), child: Text(action)),
        ],
      ),
    ),
  );
}
