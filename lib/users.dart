// Settings for the signed-in user (PIN, devices, sign out), server control on this device (an admin key from a
// `getaload admin` code), and, with server control, the household's users.
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
  late final Api _admin = Api(widget.server.asAdmin); // adding and removing people, other people's PINs
  String _me = ''; // my user id
  List<Map<String, dynamic>> _devices = [], _users = [], _adminDevices = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    _admin.close();
    super.dispose();
  }

  List<Map<String, dynamic>> _list(dynamic v) => (v as List? ?? []).cast<Map<String, dynamic>>();

  Future<void> _load() async {
    try {
      final me = await _api.call('GET', '/v1/me');
      final ds = _list(await _api.call('GET', '/v1/devices'));
      final admin = widget.server.adminKey.isNotEmpty;
      final us = admin ? _list(await _api.call('GET', '/v1/users')) : <Map<String, dynamic>>[];
      var ads = <Map<String, dynamic>>[];
      if (admin) {
        try {
          ads = _list(await _admin.call('GET', '/v1/admin/devices'));
        } catch (_) {
          // The key was taken away (another device or the command line): offer to forget it here.
          ads = [
            {'name': 'This device (no longer accepted)', 'current': true},
          ];
        }
      }
      if (mounted) {
        setState(() {
          _me = me['id'];
          _devices = ds;
          _users = us;
          _adminDevices = ads;
        });
      }
    } catch (_) {} // an older server, offline, or a key taken away elsewhere: the rows stay as they were
  }

  // Trades a one-time code from `sudo getaload admin` for this device's admin key.
  Future<void> _getControl() async {
    final code = TextEditingController();
    final ok = await confirm(
      context,
      title: 'Server control',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('On the server, run "sudo getaload admin" and enter the code it shows. It works once.'),
          const SizedBox(height: 12),
          TextField(
            controller: code,
            autofocus: true,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Code', hintText: 'XXXX-XXXX'),
          ),
        ],
      ),
      action: 'Get control',
    );
    if (!ok) return;
    try {
      final out = await _api.call('POST', '/v1/admin/claim', {
        'code': code.text.trim(),
        'device': await widget.servers.deviceName(),
      });
      await widget.servers.add(widget.server.copyWith(adminKey: out['token'])); // settings rebuild with the key
      _toast('This device now controls ${widget.server.name}');
    } catch (e) {
      _toast(e.toString());
    }
  }

  // Takes the admin key from a device; for this one, also forgets it here (even if the server already did).
  Future<void> _removeControl(Map<String, dynamic> d) async {
    final mine = d['current'] == true;
    final ok = await confirm(
      context,
      title: mine ? 'Give up server control here?' : 'Take server control from ${d['name']}?',
      body: Text(
        mine ? 'Your downloads and files stay. A new code brings control back.' : 'Use this for a lost device.',
      ),
      action: 'Remove',
      danger: true,
    );
    if (!ok) return;
    try {
      await _admin.call('DELETE', '/v1/admin/devices/${Uri.encodeComponent(d['name'])}');
    } catch (e) {
      if (!mine) return _toast(e.toString());
    }
    if (mine) return widget.servers.add(widget.server.copyWith(adminKey: ''));
    await _load();
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
      () => _admin.call('POST', '/v1/users', {'name': name.text.trim(), 'pin': r.pin}),
      '${name.text.trim()} can now sign in on their own phone: server ${widget.server.url}, their name and this PIN',
    );
  }

  Future<void> _resetPin(Map<String, dynamic> u) async {
    if (u['id'] == _me) return _changePin(); // your own always needs the current one
    final r = await _pinDialog(context, 'New PIN for ${u['name']}');
    if (r == null) return;
    await _act(() => _admin.call('PUT', '/v1/admin/users/${u['id']}/pin', {'pin': r.pin}), 'PIN changed');
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
    await _act(() => _admin.call('DELETE', '/v1/users/${u['id']}?deleteFiles=$files'), '${u['name']} removed');
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
        SettingsGroup(
          title: 'Server control',
          description: widget.server.adminKey.isEmpty
              ? 'Adding people, updates and add-ons need server control. Your own downloads, files and Google Drive '
                    'never do.'
              : 'This device can add people, update the server and change add-ons. Devices with control:',
          children: [
            if (widget.server.adminKey.isEmpty)
              SettingsRow(
                title: 'Get server control',
                subtitle: 'With a code from "sudo getaload admin" on the server',
                onTap: _getControl,
              ),
            for (final d in _adminDevices)
              SettingsRow(
                title: d['name'],
                subtitle: d['current'] == true ? 'This device' : null,
                trailing: TextButton(
                  onPressed: () => _removeControl(d),
                  child: Text('Remove', style: TextStyle(color: cs.error)),
                ),
              ),
          ],
        ),
        if (widget.server.adminKey.isNotEmpty)
          SettingsGroup(
            title: 'People on this server',
            description:
                'Each person signs in on their own phone or browser with their name and PIN, and sees only their own downloads '
                'and files (not even you see them). To switch people here, sign out above.',
            children: [
              for (final u in _users)
                SettingsRow(
                  title: u['name'],
                  trailing: PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (v) => v == 'pin' ? _resetPin(u) : _removeUser(u),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'pin', child: Text('Reset PIN')),
                      if (u['id'] != _me)
                        PopupMenuItem(
                          value: 'remove',
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
