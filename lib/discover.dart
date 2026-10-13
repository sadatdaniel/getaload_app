// Discover (experimental): titles from the user's Stremio add-ons, a title page with episodes, and a Stremio-style
// source picker. The server talks to the add-ons; torrent sources become stream-mode downloads on the server.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'launch.dart';
import 'media.dart';
import 'phone_addons.dart';
import 'ui.dart';

/// Whether the current server has add-ons switched on (drives the Discover tab). Updated by Home and Settings.
final addonsEnabled = ValueNotifier<bool>(false);

final _phoneCache = <String, List<PhoneAddon>>{};

/// The server's add-ons that this phone asks itself (refreshed by Discover, reused by the title page).
Future<List<PhoneAddon>> _phoneAddons(Api api, {bool fresh = true}) async {
  final hit = _phoneCache[api.server.url];
  if (!fresh && hit != null) return hit;
  try {
    final r = await api.call('GET', '/v1/addons');
    return _phoneCache[api.server.url] = await PhoneAddons.load(
      ((r['addons'] as List?) ?? []).cast<Map<String, dynamic>>(),
    );
  } catch (_) {
    return hit ?? [];
  }
}

class DiscoverView extends StatefulWidget {
  final Server server;
  const DiscoverView({super.key, required this.server});
  @override
  State<DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<DiscoverView> {
  late final Api _api = Api(widget.server);
  List<Map<String, dynamic>>? _rows;
  String _error = '', _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = '';
    });
    try {
      final path = _query.isEmpty ? '/v1/addons/home' : '/v1/addons/search?q=${Uri.encodeQueryComponent(_query)}';
      // Add-ons that block the server are asked from this phone (titles only; see phone_addons.dart).
      final phone = await _phoneAddons(_api);
      final results = await Future.wait([
        _api.call('GET', path).then((r) => (r as List? ?? []).cast<Map<String, dynamic>>()),
        PhoneAddons.catalogs(phone, query: _query),
      ]);
      if (mounted) setState(() => _rows = [...results[0], ...results[1]]);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _rows;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search movies and series',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear',
                        onPressed: () {
                          _search.clear();
                          _query = '';
                          _load();
                        },
                      ),
              ),
              onSubmitted: (v) {
                _query = v.trim();
                _load();
              },
            ),
          ),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(_error)),
          if (rows == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (rows != null && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _query.isEmpty
                    ? 'No catalogs yet. Add Stremio add-ons in Settings, Add-ons.'
                    : 'Nothing found for "$_query".',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          for (final r in rows ?? <Map<String, dynamic>>[]) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${r['name']}  ',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: '${r['type']} · ${r['addon']}',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: (r['metas'] as List).length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final m = (r['metas'] as List)[i] as Map<String, dynamic>;
                  return _PosterCard(
                    api: _api,
                    meta: m,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TitleScreen(server: widget.server, preview: m),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final Api api;
  final Map<String, dynamic> meta;
  final VoidCallback onTap;
  const _PosterCard({required this.api, required this.meta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 120,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 120,
                height: 178,
                child: _Poster(api: api, url: meta['poster'], name: meta['name'] ?? ''),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              meta['name'] ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

// Posters come through the server (/v1/addons/proxy): the app never contacts add-ons or their image hosts.
class _Poster extends StatelessWidget {
  final Api api;
  final String? url;
  final String name;
  const _Poster({required this.api, required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 4,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return FutureBuilder<Uint8List>(
      future: api.addonFile(url!),
      builder: (_, snap) =>
          snap.hasData ? Image.memory(snap.data!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback) : fallback,
    );
  }
}

/// A title: details, seasons and episodes (series), and the sources to watch it from.
class TitleScreen extends StatefulWidget {
  final Server server;
  final Map<String, dynamic> preview;
  const TitleScreen({super.key, required this.server, required this.preview});
  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  late final Api _api = Api(widget.server);
  late Map<String, dynamic> _meta = widget.preview;
  int? _season;
  String? _video; // the episode (or the title itself) whose sources are shown
  List<Map<String, dynamic>>? _streams;
  String _streamError = '';

  String get _type => _meta['type'] ?? 'movie';

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  List<Map<String, dynamic>> get _videos => ((_meta['videos'] as List?) ?? []).cast<Map<String, dynamic>>();

  Future<void> _loadMeta() async {
    try {
      Map<String, dynamic>? m;
      try {
        m = await _api.call(
          'GET',
          '/v1/addons/meta?type=${Uri.encodeQueryComponent(_type)}&id=${Uri.encodeQueryComponent(widget.preview['id'])}',
        );
      } catch (_) {
        m = await PhoneAddons.meta(await _phoneAddons(_api, fresh: false), _type, widget.preview['id']);
      }
      if (!mounted || m == null) return;
      setState(() => _meta = {...widget.preview, ...m!});
    } catch (_) {} // the preview is enough to show the page; sources still work
    if (_videos.isEmpty) {
      _loadStreams(_meta['id']);
    } else if (mounted) {
      final seasons = _videos.map((v) => (v['season'] as int?) ?? 0).toSet().toList()..sort();
      setState(() => _season = seasons.firstWhere((s) => s > 0, orElse: () => seasons.first));
    }
  }

  Future<void> _loadStreams(String id) async {
    setState(() {
      _video = id;
      _streams = null;
      _streamError = '';
    });
    try {
      // Sources from the server's add-ons and from those this phone asks itself. Either way they are only
      // descriptions; _start hands the chosen one to the server, which does the downloading.
      final phone = await _phoneAddons(_api, fresh: false);
      final lists = await Future.wait([
        _api
            .call(
              'GET',
              '/v1/addons/streams?type=${Uri.encodeQueryComponent(_type)}&id=${Uri.encodeQueryComponent(id)}',
            )
            .then((r) => (r as List).cast<Map<String, dynamic>>()),
        PhoneAddons.streams(phone, _type, id),
      ]);
      if (mounted && _video == id) setState(() => _streams = [...lists[0], ...lists[1]]);
    } catch (e) {
      if (mounted) setState(() => _streamError = e.toString());
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String get _title {
    final v = _videos.where((v) => v['id'] == _video).firstOrNull;
    if (v == null) return _meta['name'] ?? '';
    return '${_meta['name']} S${v['season']}E${v['episode']}';
  }

  // Every source plays through the server: it downloads the torrent or link (stream mode: in playback order) and
  // the app plays the server's stream link. External links (legal streaming services) open in the browser.
  // mode "standard" just downloads it to the server.
  Future<void> _start(Map<String, dynamic> s, {bool download = false}) async {
    try {
      final r = await _api.call('POST', '/v1/addons/play', {
        'stream': s,
        'name': _title,
        'mode': download ? 'standard' : 'stream',
      });
      if (r['external'] != null) {
        // Only web pages: a magnet: here would hand the torrent to a torrent app on the phone.
        final u = Uri.tryParse(r['external']);
        if (u == null || (u.scheme != 'https' && u.scheme != 'http')) {
          return _toast('This source can\'t be opened here.');
        }
        await launchUrl(u, mode: LaunchMode.externalApplication);
        return;
      }
      if (download) {
        _toast('Downloading on the server (see Downloads)');
        return;
      }
      final job = r['job'] as Map<String, dynamic>;
      var url = (await _api.signedJobUrl(job['id'])).toString();
      final idx = r['fileIdx'] as int? ?? -1;
      if (idx >= 0) url += '&file=$idx';
      final item = Playable(
        id: 'addon:$_video',
        title: _title,
        url: url,
        via: _api.server,
        source: {'addonType': _type, 'addonId': _video ?? ''},
      );
      if (mounted) await play(context, item);
    } catch (e) {
      _toast(e.toString());
    }
  }

  void _sourceMenu(Map<String, dynamic> s, Offset at) {
    showContextMenu(context, at, title: s['name'] ?? 'Source', [
      MenuAction('Play', icon: Icons.play_arrow, onTap: () => _start(s)),
      if (s['infoHash'] != null || s['url'] != null)
        MenuAction('Download to the server', icon: Icons.download, onTap: () => _start(s, download: true)),
      if (s['url'] is String && (s['url'] as String).startsWith(RegExp(r'https?://'))) // never a magnet
        MenuAction(
          'Copy link',
          icon: Icons.link,
          onTap: () => Clipboard.setData(ClipboardData(text: s['url'])),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = _meta;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final info = [
      if (m['releaseInfo'] != null) '${m['releaseInfo']}',
      if (m['runtime'] != null) '${m['runtime']}',
      if (m['imdbRating'] != null) '★ ${m['imdbRating']}',
    ].join('  ·  ');
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(m['name'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        if (info.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(info)),
        if ((m['genres'] as List?)?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in (m['genres'] as List).take(6))
                  Chip(label: Text('$g'), visualDensity: VisualDensity.compact),
              ],
            ),
          ),
        if ((m['description'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(m['description'], style: TextStyle(color: cs.onSurfaceVariant, height: 1.45)),
          ),
      ],
    );
    final videos = _videos.where((v) => _season == null || v['season'] == _season).toList()
      ..sort((a, b) => ((a['episode'] as int?) ?? 0).compareTo((b['episode'] as int?) ?? 0));
    final seasons = _videos.map((v) => (v['season'] as int?) ?? 0).toSet().toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text(m['name'] ?? '')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flex(
                    direction: wide ? Axis.horizontal : Axis.vertical,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: wide ? 220 : 160,
                          height: wide ? 326 : 237,
                          child: _Poster(api: _api, url: m['poster'], name: m['name'] ?? ''),
                        ),
                      ),
                      SizedBox(width: wide ? 24 : 0, height: wide ? 0 : 16),
                      if (wide) Expanded(child: header) else header,
                    ],
                  ),
                  if (_videos.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text('Episodes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        if (seasons.length > 1)
                          DropdownButton<int>(
                            value: _season,
                            items: [
                              for (final s in seasons)
                                DropdownMenuItem(value: s, child: Text(s == 0 ? 'Specials' : 'Season $s')),
                            ],
                            onChanged: (s) => setState(() => _season = s),
                          ),
                      ],
                    ),
                    SettingsGroup(
                      children: [
                        for (final v in videos)
                          SettingsRow(
                            title: '${v['episode'] ?? ''}. ${v['title'] ?? v['name'] ?? ''}',
                            subtitle: (v['released'] ?? '').toString().split('T').first,
                            trailing: _video == v['id'] ? Icon(Icons.play_circle, color: cs.primary) : null,
                            onTap: () => _loadStreams(v['id']),
                          ),
                      ],
                    ),
                  ],
                  if (_video != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      _videos.isEmpty ? 'Sources' : 'Sources for $_title',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'From your add-ons. Your server downloads the source while you watch; this device only streams from your server.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                    if (_streams == null && _streamError.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_streamError.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(_streamError)),
                    if (_streams != null && _streams!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'None of your add-ons has a source for this.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    if (_streams?.isNotEmpty == true)
                      SettingsGroup(
                        children: [
                          for (final s in _streams!)
                            ContextMenuArea(
                              onMenu: (at) => _sourceMenu(s, at),
                              child: SettingsRow(
                                title: (s['name'] ?? s['addon'] ?? 'Source').toString().replaceAll('\n', ' '),
                                subtitle: [
                                  (s['description'] ?? s['title'] ?? '').toString(),
                                  '${s['infoHash'] != null
                                          ? 'Torrent'
                                          : s['url'] != null
                                          ? 'Direct link'
                                          : s['externalUrl'] != null
                                          ? 'Opens in the browser'
                                          : 'Not playable here'}'
                                      ' · ${s['addon'] ?? ''}',
                                ].where((x) => x.isNotEmpty).join('\n'),
                                trailing: Builder(
                                  builder: (b) => IconButton(
                                    icon: const Icon(Icons.more_vert),
                                    tooltip: 'Options',
                                    onPressed: () => _sourceMenu(s, anchorOf(b)),
                                  ),
                                ),
                                onTap: s['infoHash'] != null || s['url'] != null || s['externalUrl'] != null
                                    ? () => _start(s)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mentions a real limit once in the UI (kept here so Settings and Discover say the same thing).
const p2pNote =
    'Torrent sources share what you download with others while it runs. Only use add-ons whose '
    'content you are allowed to watch.';
