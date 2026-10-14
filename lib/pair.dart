// Adding a server and signing in: the server address, then name + PIN. A server without users takes a token from
// `getaload setup` instead.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'servers.dart';

class AddServerScreen extends StatefulWidget {
  final Servers servers;
  final bool first; // no server yet: show a welcome text instead of a back button
  final String? initialUrl; // signing in again to a known server
  const AddServerScreen({super.key, required this.servers, this.first = false, this.initialUrl});

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  late final _url = TextEditingController(text: widget.initialUrl ?? '');
  final _token = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String _error = '';
  Server? _target; // the server being signed in to (address and certificate known)
  List<Map<String, dynamic>> _users = []; // names to sign in as; empty = a server without users (token)
  String _who = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _continue());
    } else if (kIsWeb && widget.first) {
      _sameOrigin();
    }
  }

  // The web client served by a GetALoad server: that server is the one to sign in to, so skip the address step.
  Future<void> _sameOrigin() async {
    final here = Uri.base.origin;
    final api = Api(Server(url: here, token: '', name: Uri.base.host));
    try {
      await api.call('GET', '/v1/health');
      if (!mounted) return;
      _url.text = here;
      await _run(() => _connect(Server(url: here, token: '', name: Uri.base.host)));
    } catch (_) {
      // a dev server or another site: the address step stays
    } finally {
      api.close();
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Checks the token against the server before saving, so a problem shows up here and not later.
  Future<void> _save(Server s) async {
    final api = Api(s);
    try {
      await api.call('GET', '/v1/jobs');
    } finally {
      api.close();
    }
    await widget.servers.add(s);
    if (Api.unauthorized.value == s.url) Api.unauthorized.value = null;
    if (mounted && !widget.first) Navigator.pop(context);
  }

  // Address and certificate are known: ask who is signing in, or save a pairing token on a server without users.
  Future<void> _connect(Server s) async {
    final api = Api(s.copyWith(token: ''));
    List<Map<String, dynamic>> users;
    try {
      users = ((await api.call('GET', '/v1/users')) as List? ?? []).cast<Map<String, dynamic>>();
    } on ApiError catch (e) {
      if (e.status != 404) rethrow;
      users = []; // a server from before users existed
    } finally {
      api.close();
    }
    if (users.isEmpty && s.token.isNotEmpty) return _save(s);
    final known = widget.servers.list.where((x) => x.url == s.url).firstOrNull?.user ?? '';
    setState(() {
      _target = s;
      _users = users;
      _who = users.length == 1
          ? users.first['name']
          : users.any((u) => u['name'] == known)
          ? known
          : '';
    });
  }

  Future<void> _continue() async {
    final url = Server.normalizeUrl(_url.text);
    if (url == null) return setState(() => _error = 'Enter the server address.');
    await _run(() async {
      final fp = await Api.probeFingerprint(url);
      final saved = widget.servers.list.where((s) => s.url == url).firstOrNull;
      if (fp.isNotEmpty && saved?.fp != fp && mounted) {
        // Trust on first use, but only after the person compares it with what the server printed.
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(saved == null ? 'Self-signed certificate' : 'The certificate changed'),
            content: SelectableText(
              'Fingerprint (SHA-256):\n\n$fp\n\n'
              'Compare it with the one shown by the installer or "sudo getaload connect". Trust this server?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Trust')),
            ],
          ),
        );
        if (ok != true) return;
      }
      await _connect(Server(url: url, token: '', fp: fp, name: saved?.name ?? Uri.parse(url).host));
    });
  }

  Future<void> _signIn() async {
    final s = _target!;
    if (_users.isEmpty) {
      if (_token.text.trim().isEmpty) return setState(() => _error = 'Enter a token.');
      return _run(() => _save(s.copyWith(token: _token.text.trim())));
    }
    if (_who.isEmpty) return setState(() => _error = 'Choose who you are.');
    if (!RegExp(r'^\d{4}$').hasMatch(_pin.text)) return setState(() => _error = 'The PIN has 4 digits.');
    await _run(() async {
      final api = Api(s.copyWith(token: ''));
      final Map<String, dynamic> out;
      try {
        out = await api.call('POST', '/v1/login', {
          'name': _who,
          'pin': _pin.text,
          'device': await widget.servers.deviceName(),
        });
      } finally {
        api.close();
        _pin.clear();
      }
      final u = out['user'] as Map<String, dynamic>;
      // The admin key belongs to this device, not to whoever signs in: it stays.
      final key = widget.servers.list.where((x) => x.url == s.url).firstOrNull?.adminKey ?? '';
      await _save(s.copyWith(token: out['token'], user: u['name'], adminKey: key));
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = _target;
    // A centered card of fixed width, like a sign-in page: fields never stretch across a wide window.
    return Scaffold(
      appBar: widget.first ? null : AppBar(title: Text(t == null ? 'Add server' : 'Sign in')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.first || t != null) ...[
                      Icon(Icons.downloading, size: 40, color: cs.primary),
                      const SizedBox(height: 12),
                      Text(
                        t == null ? 'GetALoad' : t.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t == null
                            ? 'Enter your server\'s address, e.g. https://203.0.113.5:8080. '
                                  '"sudo getaload connect" on the server shows it.'
                            : _users.isEmpty
                            ? 'This server has no users yet. Enter a token from "getaload setup".'
                            : 'Who is signing in?',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (t == null) ..._addressStep() else ..._signInStep(),
                    if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
                    if (_error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(_error, style: TextStyle(color: cs.error)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _addressStep() => [
    TextField(
      controller: _url,
      keyboardType: TextInputType.url,
      autocorrect: false,
      onSubmitted: (_) => _busy ? null : _continue(),
      decoration: const InputDecoration(labelText: 'Server address', hintText: 'https://203.0.113.5:8080'),
    ),
    const SizedBox(height: 12),
    FilledButton(onPressed: _busy ? null : _continue, child: const Text('Continue')),
  ];

  List<Widget> _signInStep() => [
    if (_users.isEmpty)
      TextField(
        controller: _token,
        autocorrect: false,
        obscureText: true,
        onSubmitted: (_) => _busy ? null : _signIn(),
        decoration: const InputDecoration(labelText: 'Token'),
      )
    else ...[
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final u in _users)
            ChoiceChip(
              label: Text(u['name']),
              selected: _who == u['name'],
              onSelected: (_) => setState(() => _who = u['name']),
            ),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _pin,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, letterSpacing: 12),
        onSubmitted: (_) => _busy ? null : _signIn(),
        decoration: const InputDecoration(labelText: 'PIN'),
      ),
    ],
    const SizedBox(height: 12),
    FilledButton(onPressed: _busy ? null : _signIn, child: Text(_users.isEmpty ? 'Connect' : 'Sign in')),
    const SizedBox(height: 4),
    TextButton(onPressed: _busy ? null : () => setState(() => _target = null), child: const Text('Another server')),
  ];
}
