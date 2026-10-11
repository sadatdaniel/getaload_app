// File manager for one server: browse folders and archives, rename, move, copy, delete, copy to Drive,
// download to the phone, share a link.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'jobs.dart' show fmtBytes;
import 'phone.dart';

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
  }

  @override
  void dispose() {
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
      _load();
    } catch (e) {
      _toast(e.toString());
    }
  }

  String _join(String dir, String name) => dir == '/' ? '/$name' : '$dir/$name';
  String _parent(String p) => p.lastIndexOf('/') <= 0 ? '/' : p.substring(0, p.lastIndexOf('/'));

  void _open(FileEntry e) {
    if (e.dir) return _go(_Place(e.archive == null ? e.path : e.path, e.archive));
    if (e.isArchive) return _go(_Place('.', e.path));
    _menu(e);
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

  Future<void> _menu(FileEntry e) async {
    final inArchive = e.archive != null;
    final a = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(e.dir ? 'Folder' : fmtBytes(e.size)),
              ),
              if (e.isArchive) _item(c, 'open', Icons.folder_zip_outlined, 'Show contents'),
              if (!e.dir) _item(c, 'download', Icons.download, Api.canDownload ? 'Download to this phone' : 'Download'),
              if (!e.dir) _item(c, 'link', Icons.link, 'Copy stream link (6 h)'),
              if (!inArchive) ...[
                _item(c, 'rename', Icons.edit_outlined, 'Rename'),
                _item(c, 'move', Icons.drive_file_move_outlined, 'Move'),
                _item(c, 'copy', Icons.copy, 'Copy'),
                _item(c, 'drive', Icons.add_to_drive, 'Copy to Google Drive'),
                _item(c, 'delete', Icons.delete_outline, 'Delete', danger: true),
              ],
            ],
          ),
        ),
      ),
    );
    switch (a) {
      case 'open':
        _open(e);
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
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('Delete ${e.name}?'),
            content: Text(
              e.dir
                  ? 'The folder and everything in it is deleted on the server.'
                  : 'The file is deleted on the server.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) await _act(() => _api.delete(e.path), 'Deleted');
    }
  }

  Widget _item(BuildContext c, String v, IconData i, String t, {bool danger = false}) {
    final color = danger ? Theme.of(c).colorScheme.error : null;
    return ListTile(
      leading: Icon(i, color: color),
      title: Text(t, style: TextStyle(color: color)),
      onTap: () => Navigator.pop(c, v),
    );
  }

  IconData _icon(FileEntry e) => e.dir
      ? Icons.folder
      : e.isArchive
      ? Icons.folder_zip
      : e.isVideo
      ? Icons.movie_outlined
      : e.isAudio
      ? Icons.music_note_outlined
      : Icons.insert_drive_file_outlined;

  @override
  Widget build(BuildContext context) {
    final h = _here;
    final title = h.archive != null ? '${h.archive!.split('/').last}${h.path == '.' ? '' : '/${h.path}'}' : h.path;
    return PopScope(
      canPop: _stack.length == 1,
      onPopInvokedWithResult: (didPop, _) => didPop ? null : _up(),
      child: Column(
        children: [
          ListTile(
            leading: _stack.length > 1
                ? IconButton(icon: const Icon(Icons.arrow_upward), tooltip: 'Up', onPressed: _up)
                : const Icon(Icons.storage),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              _error.isNotEmpty && (_entries?.isNotEmpty ?? false)
                  ? 'Showing the saved list: $_error'
                  : h.archive != null
                  ? 'Inside an archive (read-only)'
                  : _free,
            ),
            trailing: h.archive == null
                ? IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: 'New folder',
                    onPressed: () async {
                      final n = await _ask('New folder', '', 'Create');
                      if (n != null && n.isNotEmpty) await _act(() => _api.mkdir(_join(h.path, n)), 'Created');
                    },
                  )
                : null,
          ),
          const Divider(height: 1),
          Expanded(
            child: _entries == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: _entries!.isEmpty ? 1 : _entries!.length,
                      itemBuilder: (_, i) {
                        if (_entries!.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(child: Text(_error.isNotEmpty ? _error : 'Empty folder')),
                          );
                        }
                        final e = _entries![i];
                        return ListTile(
                          leading: Icon(_icon(e)),
                          title: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: e.dir ? null : Text(fmtBytes(e.size)),
                          onTap: () => _open(e),
                          onLongPress: () => _menu(e),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert),
                            tooltip: 'Actions',
                            onPressed: () => _menu(e),
                          ),
                        );
                      },
                    ),
                  ),
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
