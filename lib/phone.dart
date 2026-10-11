// Files downloaded from a server to this phone, and the downloads in progress.
// ponytail: downloads run inside the app process; closing the app stops them and there is no resume.
// Upgrade with a foreground service (or background_downloader with the pinned client) when large files need it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'jobs.dart' show fmtBytes;
import 'media.dart';
import 'launch.dart';

class PhoneDownload {
  final String name;
  int received = 0, total = -1;
  String error = '';
  PhoneDownload(this.name);
}

class PhoneDownloads extends ChangeNotifier {
  static final instance = PhoneDownloads();
  final active = <PhoneDownload>[];

  /// The app's download folder (Android: `Android/data/<app>/files/downloads`, visible over USB).
  static Future<Directory> dir() async {
    final d = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    await d.create(recursive: true);
    return d;
  }

  Future<void> start(Server s, FileEntry e) async {
    final d = PhoneDownload(e.name);
    active.add(d);
    notifyListeners();
    final api = Api(s);
    try {
      final folder = await dir();
      var target = '${folder.path}/${e.name}';
      for (var i = 1; await File(target).exists(); i++) {
        final dot = e.name.lastIndexOf('.');
        target = dot > 0
            ? '${folder.path}/${e.name.substring(0, dot)} ($i)${e.name.substring(dot)}'
            : '${folder.path}/${e.name} ($i)';
      }
      var last = DateTime.now();
      await api.downloadTo(e, target, (got, total) {
        d.received = got;
        d.total = total;
        if (DateTime.now().difference(last).inMilliseconds > 250) {
          last = DateTime.now();
          notifyListeners();
        }
      });
      active.remove(d);
    } catch (x) {
      d.error = x.toString();
    } finally {
      api.close();
      notifyListeners();
    }
  }

  void dismiss(PhoneDownload d) {
    active.remove(d);
    notifyListeners();
  }
}

/// "On this phone": downloads in progress and the files already saved.
class PhoneView extends StatefulWidget {
  const PhoneView({super.key});
  @override
  State<PhoneView> createState() => _PhoneViewState();
}

class _PhoneViewState extends State<PhoneView> {
  List<File> _files = [];
  final _p = PhoneDownloads.instance;

  @override
  void initState() {
    super.initState();
    _p.addListener(_list);
    _list();
  }

  @override
  void dispose() {
    _p.removeListener(_list);
    super.dispose();
  }

  Future<void> _list() async {
    final d = await PhoneDownloads.dir();
    final fs = d.listSync().whereType<File>().where((f) => !f.path.endsWith('.part')).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    if (mounted) setState(() => _files = fs);
  }

  @override
  Widget build(BuildContext context) {
    String name(File f) => f.uri.pathSegments.last;
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final d in _p.active)
          ListTile(
            leading: Icon(d.error.isEmpty ? Icons.downloading : Icons.error_outline),
            title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: d.error.isNotEmpty
                ? Text(d.error)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: d.total > 0 ? d.received / d.total : null),
                      const SizedBox(height: 4),
                      Text(d.total > 0 ? '${fmtBytes(d.received)} / ${fmtBytes(d.total)}' : fmtBytes(d.received)),
                    ],
                  ),
            trailing: d.error.isNotEmpty
                ? IconButton(icon: const Icon(Icons.close), onPressed: () => _p.dismiss(d))
                : null,
          ),
        if (_files.isEmpty && _p.active.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Nothing on this phone yet. In Files, open a file\'s menu and choose "Download to this phone".',
              ),
            ),
          ),
        for (final f in _files)
          ListTile(
            leading: const Icon(Icons.phone_android),
            onTap: () => play(context, Playable(id: 'file:${f.path}', title: name(f), url: f.path)),
            title: Text(name(f), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(fmtBytes(f.lengthSync())),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete from this phone',
              onPressed: () async {
                await f.delete();
                _list();
              },
            ),
          ),
      ],
    );
  }
}
