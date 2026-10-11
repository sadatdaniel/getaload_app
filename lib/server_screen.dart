// One server: name, version, Google Drive connection, remove.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'servers.dart';

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
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Remove ${widget.server.name}?'),
        content: const Text(
          'The app forgets this server. Downloads on the server stay. '
          'Pair again to add it back.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.servers.remove(widget.server); // the home screen switches to the next server
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.server;
    final status = _drive?['status'];
    return ListView(
      shrinkWrap: true, // embedded in the Settings list
      physics: const NeverScrollableScrollPhysics(),
      children: [
        ListTile(title: const Text('Address'), subtitle: Text(s.url)),
        if (_version.isNotEmpty) ListTile(title: const Text('Server version'), subtitle: Text(_version)),
        if (s.fp.isNotEmpty)
          ListTile(
            title: const Text('Certificate (pinned)'),
            subtitle: Text(s.fp, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ListTile(leading: const Icon(Icons.edit), title: const Text('Rename'), onTap: _rename),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.add_to_drive),
          title: const Text('Google Drive'),
          subtitle: Text(
            _driveError.isNotEmpty
                ? _driveError
                : status == null
                ? 'Checking...'
                : status == 'ready'
                ? 'Connected. Finished downloads can be copied there.'
                : status == 'missing-tool'
                ? 'The server is missing a helper tool: ${_drive?['reason'] ?? ''}'
                : 'Not connected',
          ),
          trailing: status != null && status != 'missing-tool'
              ? TextButton(onPressed: _connectDrive, child: Text(status == 'ready' ? 'Reconnect' : 'Connect'))
              : null,
        ),
        if (_signin != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Enter this code on the Google page (it is copied):'),
                    const SizedBox(height: 8),
                    SelectableText(_signin!['userCode'] ?? '', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    const Text('Waiting for approval...'),
                  ],
                ),
              ),
            ),
          ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
          title: const Text('Remove from this phone'),
          onTap: _remove,
        ),
      ],
    );
  }
}
