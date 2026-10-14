// "Sign in to a site": the user signs in on a web page inside the app; on Done the page's cookies go to the
// server as this user's cookies for that site (the same as importing a cookies.txt), and the phone forgets them.
// Android only: other apps' cookies (Chrome, Firefox) are out of reach, so the sign-in happens here.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'api.dart';

const _channel = MethodChannel('getaload/system');

/// "a=1; b=2" (Android's CookieManager) as Netscape cookies.txt lines for [domain] and its subdomains.
String cookiesTxt(String domain, Iterable<String> headers) {
  final seen = <String>{};
  final lines = ['# Netscape HTTP Cookie File'];
  for (final h in headers) {
    for (final part in h.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final name = part.substring(0, i).trim(), value = part.substring(i + 1).trim();
      // ponytail: Android does not say a cookie's path or expiry; "/" and session-length cover sign-in cookies.
      if (name.isNotEmpty && seen.add(name)) lines.add('.$domain\tTRUE\t/\tTRUE\t0\t$name\t$value');
    }
  }
  return lines.length == 1 ? '' : '${lines.join('\n')}\n';
}

class SiteSignInScreen extends StatefulWidget {
  final Server server;
  final String domain; // e.g. youtube.com
  const SiteSignInScreen({super.key, required this.server, required this.domain});
  @override
  State<SiteSignInScreen> createState() => _SiteSignInScreenState();
}

class _SiteSignInScreenState extends State<SiteSignInScreen> {
  WebViewController? _web;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  // A clean session every time, so nobody else's sign-in on this phone ends up on the server.
  Future<void> _start() async {
    await _forget();
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://www.${widget.domain}/'));
    if (mounted) setState(() => _web = c);
  }

  Future<void> _forget() async {
    try {
      await _channel.invokeMethod('clearCookies');
      await _web?.clearCache();
      await _web?.clearLocalStorage();
    } catch (_) {}
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    final d = widget.domain;
    final api = Api(widget.server);
    try {
      final headers = [
        for (final u in ['https://www.$d/', 'https://$d/', 'https://m.$d/'])
          (await _channel.invokeMethod<String>('cookies', {'url': u})) ?? '',
      ];
      final text = cookiesTxt(d, headers);
      if (text.isEmpty) throw Exception('No sign-in found. Sign in on the page first, then tap Done.');
      final r = await api.call('POST', '/v1/cookies', {
        'domain': d,
        'content': text,
        'userAgent': await _web?.getUserAgent() ?? '', // the server sends the matching browser name with them
      });
      await _forget();
      if (mounted) {
        Navigator.pop(context, 'Signed in: ${r['imported']} cookies saved for $d (only your downloads use them)');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      onPopInvokedWithResult: (_, _) => _forget(), // leaving without Done keeps nothing
      child: Scaffold(
        appBar: AppBar(
          title: Text('Sign in to ${widget.domain}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(onPressed: _busy || _web == null ? null : _done, child: const Text('Done')),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              color: cs.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Text(
                'Sign in on the page, then tap Done. Your session goes to your server for your downloads only, and '
                'this phone forgets it. Use a spare account. If the site says this browser is not allowed, use '
                '"Import cookies.txt" instead.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: _web == null ? const Center(child: CircularProgressIndicator()) : WebViewWidget(controller: _web!),
            ),
          ],
        ),
      ),
    );
  }
}
