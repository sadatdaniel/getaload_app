// One server: name, version, Google Drive connection, remove.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'net.dart' if (dart.library.js_interop) 'net_web.dart';
import 'servers.dart';
import 'ui.dart';

class ServerScreen extends StatefulWidget {
  final Servers servers;
  final Server server;
  const ServerScreen({super.key, required this.servers, required this.server});
  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final Api _api = Api(widget.server);
  String _version = '';
  Map<String, dynamic>? _drive; // the gdrive provider as /v1/providers reports it
  String _driveError = '';
  Map<String, dynamic>? _signin; // userCode + verificationUrl while waiting for Google
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPorts();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final h = await _api.call('GET', '/v1/health');
      final ps = (await _api.call('GET', '/v1/providers') as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _version = h['version'] ?? '';
        _drive = ps.where((p) => p['name'] == 'gdrive').firstOrNull;
        _driveError = '';
      });
    } catch (e) {
      if (mounted) setState(() => _driveError = e.toString());
    }
  }

  // Google's device flow: the server asks Google for a code, the user approves it in any browser.
  // Works from the phone because nothing has to redirect back to the server.
  Future<void> _connectDrive() async {
    try {
      if (_drive?['enabled'] != true) await _api.call('PUT', '/v1/providers/gdrive/enabled', {'enabled': true});
      final si = await _api.call('POST', '/v1/providers/gdrive/signin') as Map<String, dynamic>;
      setState(() => _signin = si);
      await Clipboard.setData(ClipboardData(text: si['userCode']));
      await launchUrl(Uri.parse(si['verificationUrl']), mode: LaunchMode.externalApplication);
      _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
        try {
          final st = await _api.call('GET', '/v1/providers/gdrive/signin');
          if (st['state'] == 'pending') return;
          _poll?.cancel();
          if (!mounted) return;
          setState(() => _signin = null);
          _toast(st['state'] == 'done' ? 'Google Drive connected' : 'Sign-in failed: ${st['error'] ?? ''}');
          _load();
        } catch (_) {}
      });
    } catch (e) {
      _toast(e.toString());
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: widget.server.name);
    final n = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Name'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (n != null && n.isNotEmpty) await widget.servers.rename(widget.server, n);
  }

  Future<void> _remove() async {
    final ok = await confirm(
      context,
      title: 'Remove ${widget.server.name}?',
      body: const Text('The app forgets this server. Downloads on the server stay. Pair again to add it back.'),
      action: 'Remove',
      danger: true,
    );
    if (!ok) return;
    await widget.servers.remove(widget.server); // the home screen switches to the next server
  }

  // ---- ports ----

  Map<String, dynamic>? _ports;
  bool _portsLoaded = false;
  String _probe = '';

  Future<void> _loadPorts() async {
    try {
      final p = await _api.call('GET', '/v1/ports') as Map<String, dynamic>;
      if (mounted) setState(() => _ports = p);
    } catch (_) {
      // older servers have no port check
    } finally {
      if (mounted) setState(() => _portsLoaded = true);
    }
  }

  // The outside view: connect to the torrent port from this device. Only meaningful when this device is not on
  // the server's own network or tunnel (a 127.0.0.1 or LAN address proves nothing about the internet).
  Future<void> _testPort() async {
    final host = Uri.parse(widget.server.url).host;
    final port = _ports?['torrentPort'] as int? ?? 0;
    setState(() => _probe = 'Testing…');
    final ok = await probeTcp(host, port);
    if (!mounted) return;
    final local =
        host == 'localhost' || host.startsWith('127.') || host.startsWith('192.168.') || host.startsWith('10.');
    setState(
      () => _probe = ok
          ? 'Port $port is reachable from this device.'
                '${local ? ' This device is on the same network or tunnel, so it says nothing about the internet.' : ''}'
          : 'Port $port is not reachable from this device. Open TCP and UDP $port in the cloud firewall and on the server.',
    );
  }

  Widget _verdict(String? v) {
    final cs = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (v) {
      'open' => ('Open', cs.tertiaryContainer, cs.onTertiaryContainer),
      'probably-closed' => ('Probably closed', cs.errorContainer, cs.onErrorContainer),
      'not-running' => ('Not running', cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ => ('Unknown', cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.server;
    final status = _drive?['status'];
    final p = _ports;
    final cs = Theme.of(context).colorScheme;
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: cs.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Server',
          children: [
            SettingsRow(title: 'Name', subtitle: s.name, onTap: _rename),
            SettingsRow(
              title: 'Address',
              trailing: SelectableText(s.url, style: mono),
            ),
            if (_version.isNotEmpty) SettingsRow(title: 'Version', trailing: Text(_version)),
            if (s.fp.isNotEmpty)
              SettingsRow(
                title: 'Certificate',
                subtitle: 'Pinned SHA-256 fingerprint',
                below: SelectableText(s.fp, style: mono),
              ),
          ],
        ),
        SettingsGroup(
          title: 'Network',
          description: 'Torrents are faster when other peers can connect to this server.',
          children: [
            if (p == null)
              SettingsRow(
                title: 'Torrent port',
                subtitle: _portsLoaded ? 'Update the server to check ports.' : 'Checking…',
              )
            else ...[
              SettingsRow(
                title: 'Torrent port ${p['torrentPort']}',
                subtitle: p['hint'],
                trailing: _verdict(p['verdict']),
              ),
              if (p['torrentRunning'] == true)
                SettingsRow(title: 'Peers', trailing: Text('${p['peers']} connected, ${p['incoming']} came to us')),
              if (Api.canDownload)
                SettingsRow(
                  title: 'Test from this device',
                  subtitle: _probe.isEmpty ? 'Connects to the port from this phone, e.g. over mobile data.' : _probe,
                  trailing: OutlinedButton(onPressed: _testPort, child: const Text('Test')),
                ),
              SettingsRow(
                title: 'Check again',
                trailing: IconButton(onPressed: _loadPorts, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
              ),
            ],
          ],
        ),
        SettingsGroup(
          title: 'Cloud storage',
          children: [
            SettingsRow(
              title: 'Google Drive',
              subtitle: _driveError.isNotEmpty
                  ? _driveError
                  : status == null
                  ? 'Checking…'
                  : status == 'ready'
                  ? 'Connected. Finished downloads can be copied there.'
                  : status == 'missing-tool'
                  ? 'The server is missing a helper tool: ${_drive?['reason'] ?? ''}'
                  : 'Not connected',
              trailing: status != null && status != 'missing-tool'
                  ? OutlinedButton(onPressed: _connectDrive, child: Text(status == 'ready' ? 'Reconnect' : 'Connect'))
                  : null,
              below: _signin == null
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Enter this code on the Google page (it is copied):'),
                        const SizedBox(height: 6),
                        SelectableText(_signin!['userCode'] ?? '', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Text('Waiting for approval…', style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
            ),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsRow(
              title: 'Remove this server from the app',
              subtitle: 'Downloads on the server stay. Pair again to add it back.',
              danger: true,
              onTap: _remove,
            ),
          ],
        ),
      ],
    );
  }
}
