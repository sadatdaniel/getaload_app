// The download queue of one server, with live progress from /v1/events.
import 'dart:async';

import 'package:flutter/material.dart';

import 'add.dart';
import 'api.dart';
import 'launch.dart';
import 'media.dart';
import 'ui.dart';

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
        if (changed) {
          _load();
          Api.filesChanged.value++; // a download started or finished: Media and Files show it without a refresh
        }
      },
      onError: (e) => e is ApiError && e.status == 401
          ? setState(() => _error = e.toString())
          : _reconnect(), // a dead token: stop retrying
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
      Api.filesChanged.value++;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // Plays through the job stream, which waits for missing bytes (and fetches torrent pieces under the playhead).
  Future<void> _playJob(Map<String, dynamic> j) async {
    try {
      final url = (await _api.signedJobUrl(j['id'])).toString();
      final name = (j['name'] as String?)?.isNotEmpty == true ? j['name'] as String : 'Download';
      final item = Playable(id: 'job:${_api.server.url}:${j['id']}', title: name, url: url, via: _api.server);
      if (mounted) await play(context, item);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _remove(Map<String, dynamic> j) async {
    // Unfinished: the partial data is useless on its own, so deleting it is the default (like qBittorrent).
    final st = j['state'];
    var files = st != 'done' && st != 'seeding';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Remove download?'),
          content: CheckboxListTile(
            value: files,
            onChanged: (v) => set(() => files = v ?? false),
            title: const Text('Also delete its files on the server'),
            subtitle: const Text('Unfinished downloads: the partial data cannot be resumed once removed.'),
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

  // The only way to put something on the server: queue a download (see add.dart). No uploads.
  final _panel = GlobalKey<AddPanelState>();

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
          child: Center(
            child: Text(
              'Nothing downloading. Add a link above, drop .torrent files here, or copy a link and reopen the app.',
            ),
          ),
        ),
      ];
    } else {
      items = [for (final j in _jobs!) _tile(j)];
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: TorrentDropTarget(
        panel: _panel,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            AddPanel(key: _panel, api: _api, onAdded: _load),
            ...items,
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> j) {
    final p = _live[j['id']];
    final done = (p?['done'] ?? j['done'] ?? 0) as num;
    final total = (p?['total'] ?? j['total'] ?? 0) as num;
    final state = j['state'] as String? ?? '';
    final paused = j['want'] == 'paused';
    final cs = Theme.of(context).colorScheme;
    final parts = <String>[
      if (total > 0) '${fmtBytes(done)} of ${fmtBytes(total)}' else if (done > 0) fmtBytes(done),
      if (p != null && (p['rate'] ?? 0) > 0) '${fmtBytes(p['rate'])}/s',
      if (p != null && (p['peers'] ?? 0) > 0) '${p['peers']} peers',
      if ((p?['hint'] ?? '') != '') p!['hint'],
      if ((j['error'] ?? '') != '') j['error'],
    ];
    final (IconData kindIcon, Color kindColor) = switch (j['kind']) {
      'torrent' => (Icons.hub, const Color(0xFF4F8FD6)),
      'video' => (Icons.smart_display, const Color(0xFFD0605E)),
      'copy' => (Icons.cloud_upload, const Color(0xFF43A6A0)),
      _ => (Icons.language, const Color(0xFF8E7CC3)),
    };
    final (String label, Color bg, Color fg) = switch (state) {
      'done' => ('Done', cs.tertiaryContainer, cs.onTertiaryContainer),
      'seeding' => ('Seeding', cs.tertiaryContainer, cs.onTertiaryContainer),
      'failed' => ('Failed', cs.errorContainer, cs.onErrorContainer),
      _ when paused => ('Paused', cs.surfaceContainerHighest, cs.onSurfaceVariant),
      'queued' => ('Queued', cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ => (
        state.isEmpty ? '?' : '${state[0].toUpperCase()}${state.substring(1)}',
        cs.primaryContainer,
        cs.onPrimaryContainer,
      ),
    };
    return ContextMenuArea(
      onMenu: (at) => _jobMenu(j, at),
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kindColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(kindIcon, color: kindColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (j['name'] as String?)?.isNotEmpty == true ? j['name'] : j['source'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                          child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg)),
                        ),
                        if (total > 0 && state != 'done') ...[
                          const SizedBox(width: 8),
                          Text('${(done * 100 / total).floor()}%', style: Theme.of(context).textTheme.labelMedium),
                        ],
                      ],
                    ),
                    if (state != 'done' && state != 'failed' && state != 'seeding')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(
                          value: total > 0 ? done / total : null,
                          borderRadius: BorderRadius.circular(4),
                          minHeight: 6,
                        ),
                      ),
                    if (parts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          parts.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              Builder(
                builder: (b) => IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Actions',
                  onPressed: () => _jobMenu(j, anchorOf(b)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Desktop-style menu for a download: right click, long press or ⋮. The two download orders are tick options
  // that can be switched while it runs.
  void _jobMenu(Map<String, dynamic> j, Offset at) {
    final state = j['state'] as String? ?? '';
    final paused = j['want'] == 'paused';
    final id = j['id'];
    final canMode = (j['kind'] == 'torrent' || j['kind'] == 'web') && state != 'done' && state != 'seeding';
    Future<void> mode(String m) => _act(() => _api.call('PUT', '/v1/jobs/$id/mode', {'mode': m}));
    showContextMenu(context, at, title: (j['name'] as String?)?.isNotEmpty == true ? j['name'] : j['source'], [
      if (j['kind'] != 'copy' && state != 'failed')
        MenuAction('Play', icon: Icons.play_arrow, onTap: () => _playJob(j)),
      if (state != 'done')
        MenuAction(
          paused ? 'Resume' : 'Pause',
          icon: paused ? Icons.play_circle_outline : Icons.pause_circle_outline,
          onTap: () => _act(() => _api.call('POST', '/v1/jobs/$id/${paused ? 'resume' : 'pause'}')),
        ),
      if (canMode) ...[
        const MenuAction.divider(),
        MenuAction(
          'Play while downloading (ends first, then in order)',
          checked: j['mode'] == 'stream',
          onTap: () => mode('stream'),
        ),
        MenuAction(
          'Standard (fastest for the whole download)',
          checked: j['mode'] != 'stream',
          onTap: () => mode('standard'),
        ),
      ],
      if (j['kind'] == 'torrent' && state != 'queued') ...[
        const MenuAction.divider(),
        MenuAction(
          'Verify data',
          icon: Icons.fact_check_outlined,
          onTap: () => _act(() => _api.call('POST', '/v1/jobs/$id/recheck')),
        ),
      ],
      const MenuAction.divider(),
      MenuAction('Remove…', icon: Icons.delete_outline, danger: true, onTap: () => _remove(j)),
    ]);
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
