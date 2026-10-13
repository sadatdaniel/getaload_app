// Site sign-ins: cookies.txt files the server sends with downloads (yt-dlp and web downloads) for sites that need
// a signed-in session, e.g. YouTube when it asks a cloud server to "confirm you're not a bot". Stored encrypted on
// the server and never shown again; each user has their own.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'site_signin.dart';
import 'ui.dart';

/// The site a cookies.txt is for: its most common domain, without subdomains ("www.youtube.com" → "youtube.com").
String guessCookieDomain(String text) {
  final counts = <String, int>{};
  for (var line in const LineSplitter().convert(text)) {
    line = line.replaceFirst('#HttpOnly_', '');
    if (line.startsWith('#') || !line.contains('\t')) continue;
    final host = line.split('\t').first.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
    final parts = host.split('.');
    if (parts.length < 2) continue;
    // ponytail: last two labels; sites under co.uk-style suffixes need the domain typed in.
    final d = parts.sublist(parts.length - 2).join('.');
    counts[d] = (counts[d] ?? 0) + 1;
  }
  if (counts.isEmpty) return '';
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

class CookieSettings extends StatefulWidget {
  final Server server;
  const CookieSettings({super.key, required this.server});
  @override
  State<CookieSettings> createState() => _CookieSettingsState();
}

class _CookieSettingsState extends State<CookieSettings> {
  late final Api _api = Api(widget.server);
  List<Map<String, dynamic>>? _sites;

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
      final l = ((await _api.call('GET', '/v1/cookies')) as List? ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _sites = l);
    } catch (_) {}
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (picked.isEmpty) return;
    final text = utf8.decode(await picked.first.readAsBytes(), allowMalformed: true);
    if (!mounted) return;
    final domain = TextEditingController(text: guessCookieDomain(text));
    final ok = await confirm(
      context,
      title: 'Import cookies',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: domain,
            decoration: const InputDecoration(labelText: 'For the site', hintText: 'youtube.com'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your downloads from this site (and its subdomains) will be signed in with this session. Only yours: '
            'every user has their own. Use a spare account: sites may flag accounts that download a lot.',
          ),
        ],
      ),
      action: 'Import',
    );
    if (!ok) return;
    try {
      final r = await _api.call('POST', '/v1/cookies', {'domain': domain.text.trim(), 'content': text});
      _toast('${r['imported']} cookies saved for ${domain.text.trim()}');
    } catch (e) {
      _toast(e.toString());
    }
    _load();
  }

  // Sign in on a page inside the app (Android): its cookies become this user's cookies for the site.
  Future<void> _signIn() async {
    final domain = TextEditingController(text: 'youtube.com');
    final ok = await confirm(
      context,
      title: 'Sign in to a site',
      body: TextField(
        controller: domain,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'Site', hintText: 'youtube.com'),
      ),
      action: 'Open',
    );
    final d = domain.text.trim().toLowerCase().replaceFirst(RegExp(r'^(https?://)?(www\.)?'), '').split('/').first;
    if (!ok || d.isEmpty || !mounted) return;
    final msg = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SiteSignInScreen(server: widget.server, domain: d),
      ),
    );
    if (msg != null) _toast(msg);
    _load();
  }

  Future<void> _remove(String domain) async {
    try {
      await _api.call('DELETE', '/v1/cookies/${Uri.encodeComponent(domain)}');
    } catch (e) {
      _toast(e.toString());
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SettingsGroup(
      title: 'Site sign-ins',
      description:
          'For sites that only work signed in, e.g. YouTube asking a cloud server to "confirm you\'re not a bot". '
          'Export cookies.txt from a browser (a private window signed in to the site, then close it) and import it '
          'here. Only your downloads use them. Stored encrypted on the server; values are never shown again.',
      children: [
        for (final s in _sites ?? <Map<String, dynamic>>[])
          SettingsRow(
            title: s['domain'],
            subtitle: [
              '${s['count']} cookies',
              if ((s['expired'] ?? 0) > 0) '${s['expired']} expired: import a fresh file',
            ].join(' · '),
            trailing: TextButton(
              onPressed: () => _remove(s['domain']),
              child: Text('Remove', style: TextStyle(color: cs.error)),
            ),
          ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          SettingsRow(
            title: 'Sign in to a site',
            subtitle: 'Sign in on the site inside the app; no file needed.',
            onTap: _signIn,
          ),
        SettingsRow(title: 'Import cookies.txt', onTap: _import),
      ],
    );
  }
}
