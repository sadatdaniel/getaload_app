// Settings for the signed-in user (PIN, devices, sign out) and, for the owner, the household's users.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'pair.dart';
import 'servers.dart';
import 'ui.dart';

class AccountSettings extends StatefulWidget {
  final Servers servers;
  final Server server;
  const AccountSettings({super.key, required this.servers, required this.server});
  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  late final Api _api = Api(widget.server);
  String _me = ''; // my user id
  List<Map<String, dynamic>> _devices = [], _users = [];

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

  Future<void> _load() async {
    try {
      final me = await _api.call('GET', '/v1/me');
      final ds = ((await _api.call('GET', '/v1/devices')) as List? ?? []).cast<Map<String, dynamic>>();
      final us = widget.server.owner
          ? ((await _api.call('GET', '/v1/users')) as List? ?? []).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _me = me['id'];
          _devices = ds;
          _users = us;
        });
      }
    } catch (_) {} // an older server, or offline: the rows stay empty
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _act(Future<void> Function() f, String done) async {
    try {
      await f();
      _toast(done);
      await _load();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _changePin() async {
    final r = await _pinDialog(context, 'Change your PIN', current: true);
    if (r == null) return;
    await _act(() => _api.call('PUT', '/v1/users/$_me/pin', {'pin': r.pin, 'current': r.current}), 'PIN changed');
  }

  Future<void> _signOutDevice(Map<String, dynamic> d) async {
    final mine = d['current'] == true;
    final ok = await confirm(
      context,
      title: mine ? 'Sign out of ${widget.server.name}?' : 'Sign out ${d['name']}?',
      body: Text(mine ? 'You can sign in again with your name and PIN.' : 'That device needs your PIN to come back.'),
      action: 'Sign out',
    );
    if (!ok) return;
    try {
      await _api.call('DELETE', '/v1/devices/${Uri.encodeComponent(d['name'])}');
    } catch (e) {
      return _toast(e.toString());
    }
    if (!mine) return _load();
    if (!mounted) return;
    // Straight to the sign-in screen, so someone else can sign in on this device.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddServerScreen(servers: widget.servers, initialUrl: widget.server.url),
      ),
    );
  }

  Future<void> _addUser() async {
    final name = TextEditingController();
    final r = await _pinDialog(context, 'Add a person', name: name);
    if (r == null) return;
    await _act(
      () => _api.call('POST', '/v1/users', {'name': name.text.trim(), 'pin': r.pin}),
      '${name.text.trim()} can now sign in on their own phone: server ${widget.server.url}, their name and this PIN',
    );
  }

  Future<void> _resetPin(Map<String, dynamic> u) async {
    final r = await _pinDialog(context, 'New PIN for ${u['name']}', current: u['id'] == _me);
    if (r == null) return;
    await _act(() => _api.call('PUT', '/v1/users/${u['id']}/pin', {'pin': r.pin, 'current': r.current}), 'PIN changed');
  }

  Future<void> _removeUser(Map<String, dynamic> u) async {
    var files = false;
    final ok = await confirm(
      context,
      title: 'Remove ${u['name']}?',
      body: StatefulBuilder(
        builder: (c, set) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Their downloads stop and their devices are signed out.'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: files,
              onChanged: (v) => set(() => files = v ?? false),
              title: const Text('Also delete their files'),
            ),
          ],
        ),
      ),
      action: 'Remove',
      danger: true,
    );
    if (!ok) return;
    await _act(() => _api.call('DELETE', '/v1/users/${u['id']}?deleteFiles=$files'), '${u['name']} removed');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Your account',
          description: 'Signed in to ${widget.server.name} as ${widget.server.user}.',
          children: [
            SettingsRow(title: 'Change PIN', onTap: _changePin),
            for (final d in _devices)
              SettingsRow(
                title: d['name'],
                subtitle: d['current'] == true ? 'This device' : 'Signed in',
                trailing: TextButton(
                  onPressed: () => _signOutDevice(d),
                  child: Text('Sign out', style: TextStyle(color: cs.error)),
                ),
              ),
          ],
        ),
        if (widget.server.owner)
          SettingsGroup(
            title: 'People on this server',
            description:
                'Each person signs in on their own phone with their name and PIN, and sees only their own downloads '
                'and files (not even you see them). To switch people on this phone, sign out above.',
            children: [
              for (final u in _users)
                SettingsRow(
                  title: u['name'],
                  subtitle: u['owner'] == true ? 'Owner' : null,
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(onPressed: () => _resetPin(u), child: const Text('Reset PIN')),
                      if (u['id'] != _me)
                        TextButton(
                          onPressed: () => _removeUser(u),
                          child: Text('Remove', style: TextStyle(color: cs.error)),
                        ),
                    ],
                  ),
                ),
              SettingsRow(title: 'Add a person', subtitle: 'Choose their name and a starting PIN', onTap: _addUser),
            ],
          ),
      ],
    );
  }
}

/// Asks for a 4-digit PIN (and the current one, or a name). Null when cancelled.
Future<({String pin, String current})?> _pinDialog(
  BuildContext context,
  String title, {
  bool current = false,
  TextEditingController? name,
}) {
  final cur = TextEditingController(), pin = TextEditingController();
  String err = '';
  Widget field(TextEditingController c, String label) => TextField(
    controller: c,
    obscureText: true,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
    decoration: InputDecoration(labelText: label),
  );
  return showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (name != null)
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              if (current) field(cur, 'Current PIN'),
              field(pin, 'New PIN (4 digits)'),
              if (err.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(err, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (name != null && name.text.trim().isEmpty) return set(() => err = 'Enter a name.');
              if (pin.text.length != 4 || current && cur.text.length != 4) {
                return set(() => err = 'PINs have 4 digits.');
              }
              Navigator.pop(c, (pin: pin.text, current: cur.text));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
