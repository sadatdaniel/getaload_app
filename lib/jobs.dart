// The download queue of one server, with live progress from /v1/events.
import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';

class JobsView extends StatefulWidget {
  final Server server;
  const JobsView({super.key, required this.server});
  @override
  State<JobsView> createState() => _JobsViewState();
}

class _JobsViewState extends State<JobsView> {
  late final Api _api = Api(widget.server);
  List<Map<String, dynamic>>? _jobs;
  Map<String, Map<String, dynamic>> _live = {};
  String _error = '';
  StreamSubscription? _sub;
  Timer? _retry;
  Timer? _refresh; // catches what progress events miss: jobs added elsewhere, or failing before they ever run

  @override
  void initState() {
    super.initState();
    _load();
    _listen();
    _refresh = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _retry?.cancel();
    _refresh?.cancel();
    _api.close();
    _link.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await _api.jobs();
      if (mounted) {
        setState(() {
          _jobs = j;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // Progress only covers running jobs; when that set changes (one finished or started), reload the list.
  void _listen() {
    _sub = _api.progress().listen(
      (p) {
        final live = {for (final x in p) x['id'] as String: x};
        final changed =
            live.keys.toSet().difference(_live.keys.toSet()).isNotEmpty ||
            _live.keys.toSet().difference(live.keys.toSet()).isNotEmpty;
        if (mounted) setState(() => _live = live);
        if (changed) _load();
      },
      onError: (_) => _reconnect(),
      onDone: _reconnect,
      cancelOnError: true,
    );
  }

  void _reconnect() {
    _retry = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _load();
      _listen();
    });
  }

  Future<void> _act(Future<void> Function() f) async {
    try {
      await f();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _remove(Map<String, dynamic> j) async {
    var files = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Remove download?'),
          content: CheckboxListTile(
            value: files,
            onChanged: (v) => set(() => files = v ?? false),
            title: const Text('Also delete its files on the server'),
            contentPadding: EdgeInsets.zero,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
          ],
        ),
      ),
    );
    if (ok == true) await _act(() => _api.call('DELETE', '/v1/jobs/${j['id']}?deleteFiles=$files'));
  }

  final _link = TextEditingController();

  // The only way to put something on the server: queue a download (link, magnet, video page or .torrent).
  Future<void> _addLink() async {
    final l = _link.text.trim();
    if (l.isEmpty) return;
    await _act(() => _api.add(l));
    _link.clear();
  }

  Future<void> _addTorrent() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['torrent']);
    if (picked.isEmpty) return;
    final bytes = await picked.first.readAsBytes();
    if (bytes.isNotEmpty) await _act(() => _api.call('POST', '/v1/jobs', {'torrent': base64Encode(bytes)}));
  }

  Widget _addBox() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Column(
      children: [
        TextField(
          controller: _link,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _addLink(),
          decoration: InputDecoration(
            hintText: 'Link, video page or magnet',
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(28))),
            prefixIcon: const Icon(Icons.link),
            suffixIcon: IconButton(icon: const Icon(Icons.send), tooltip: 'Download', onPressed: _addLink),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _addTorrent,
            icon: const Icon(Icons.upload_file),
            label: const Text('.torrent file'),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final List<Widget> items;
    if (_jobs == null) {
      items = [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: _error.isEmpty
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      Text(_error, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
          ),
        ),
      ];
    } else if (_jobs!.isEmpty) {
      items = [
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No downloads yet. Paste a link above, or copy one and reopen the app.')),
        ),
      ];
    } else {
      items = [for (final j in _jobs!) _tile(j)];
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [_addBox(), const Divider(height: 1), ...items],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> j) {
    final p = _live[j['id']];
    final done = (p?['done'] ?? j['done'] ?? 0) as num;
    final total = (p?['total'] ?? j['total'] ?? 0) as num;
    final state = j['state'] as String? ?? '';
    final paused = j['want'] == 'paused';
    final parts = <String>[
      state,
      if (total > 0) '${fmtBytes(done)} / ${fmtBytes(total)}' else if (done > 0) fmtBytes(done),
      if (p != null && (p['rate'] ?? 0) > 0) '${fmtBytes(p['rate'])}/s',
      if (p != null && (p['peers'] ?? 0) > 0) '${p['peers']} peers',
      if ((p?['hint'] ?? '') != '') p!['hint'],
      if ((j['error'] ?? '') != '') j['error'],
    ];
    return ListTile(
      title: Text(
        (j['name'] as String?)?.isNotEmpty == true ? j['name'] : j['source'],
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state != 'done' && state != 'failed')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(value: total > 0 ? done / total : null),
            ),
          Text(parts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (a) => a == 'remove' ? _remove(j) : _act(() => _api.call('POST', '/v1/jobs/${j['id']}/$a')),
        itemBuilder: (_) => [
          if (state != 'done')
            PopupMenuItem(value: paused ? 'resume' : 'pause', child: Text(paused ? 'Resume' : 'Pause')),
          const PopupMenuItem(value: 'remove', child: Text('Remove')),
        ],
      ),
    );
  }
}

String fmtBytes(num n) {
  const u = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var i = 0;
  var v = n.toDouble();
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}
