// Adding a server: scan the QR from `dmn pair` / the web panel, paste its dmn://pair link, or type URL + token.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api.dart';
import 'servers.dart';

class AddServerScreen extends StatefulWidget {
  final Servers servers;
  final bool first; // no server yet: show a welcome text instead of a back button
  const AddServerScreen({super.key, required this.servers, this.first = false});

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _busy = false;
  String _error = '';

  // Checks the token against the server before saving, so a typo shows up here and not later.
  Future<void> _save(Server s) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    final api = Api(s);
    try {
      await api.call('GET', '/v1/jobs');
      await widget.servers.add(s);
      if (mounted && !widget.first) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      api.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final link = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _Scanner()));
    if (link == null) return;
    final s = Server.fromPairLink(link);
    s == null ? setState(() => _error = 'That QR code is not a download_me_not pairing code.') : _save(s);
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final s = Server.fromPairLink(text);
    s == null ? setState(() => _error = 'The clipboard has no dmn://pair link.') : _save(s);
  }

  Future<void> _manual() async {
    final url = Server.normalizeUrl(_url.text);
    if (url == null || _token.text.trim().isEmpty) {
      setState(() => _error = 'Enter the server address and a token.');
      return;
    }
    setState(() => _busy = true);
    String fp;
    try {
      fp = await Api.probeFingerprint(url);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
      return;
    }
    setState(() => _busy = false);
    if (fp.isNotEmpty && mounted) {
      // Trust on first use, but only after the owner compares it with what the server printed.
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Self-signed certificate'),
          content: SelectableText(
            'Fingerprint (SHA-256):\n\n$fp\n\n'
            'Compare it with the one shown by "dmn pair" or the web panel. Trust this server?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Trust')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _save(Server(url: url, token: _token.text.trim(), fp: fp, name: Uri.parse(url).host));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.first ? 'download_me_not' : 'Add server')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.first)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Connect to your server. In its web panel open Settings, "Pair a phone", '
                'or run "sudo dmn pair" on the server, then scan the code.',
              ),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _paste,
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste pairing link'),
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('Or enter it by hand')),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Server address', hintText: 'https://203.0.113.5:8080'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _token,
            autocorrect: false,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Token'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: _busy ? null : _manual, child: const Text('Connect')),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

class _Scanner extends StatefulWidget {
  const _Scanner();
  @override
  State<_Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<_Scanner> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing code')),
      body: MobileScanner(
        onDetect: (capture) {
          final v = capture.barcodes
              .map((b) => b.rawValue)
              .whereType<String>()
              .where((s) => s.startsWith('dmn://'))
              .firstOrNull;
          if (v != null && !_done) {
            _done = true;
            Navigator.pop(context, v);
          }
        },
      ),
    );
  }
}
