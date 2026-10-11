import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'jobs.dart';
import 'pair.dart';
import 'server_screen.dart';
import 'servers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final servers = Servers();
  await servers.load();
  runApp(App(servers: servers));
}

class App extends StatelessWidget {
  final Servers servers;
  const App({super.key, required this.servers});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3B82F6);
    return MaterialApp(
      title: 'download_me_not',
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: ListenableBuilder(
        listenable: servers,
        builder: (_, _) => servers.current == null
            ? AddServerScreen(servers: servers, first: true)
            : Home(servers: servers),
      ),
    );
  }
}

class Home extends StatefulWidget {
  final Servers servers;
  const Home({super.key, required this.servers});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  Servers get servers => widget.servers;
  bool _offering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkClipboard();
  }

  // Android 10+ lets only the focused app read the clipboard, so wait until the window has focus.
  Future<void> _checkClipboard() async {
    if (_offering) return;
    _offering = true;
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      final text = ((await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '').trim();
      if (text.isEmpty || text == servers.lastClip || !mounted) return;
      final pair = Server.fromPairLink(text);
      if (pair == null && !isDownloadLink(text)) return;
      await servers.seenClip(text);
      if (pair != null) {
        await _offerPair(pair);
      } else {
        await _offerDownload(text);
      }
    } finally {
      _offering = false;
    }
  }

  Future<void> _offerPair(Server s) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => _Sheet(
        title: 'Add server ${s.name}?',
        body: Text('The clipboard has a pairing link for ${s.url}.'),
        action: 'Add',
      ),
    );
    if (ok != true) return;
    final api = Api(s);
    try {
      await api.call('GET', '/v1/jobs');
      await servers.add(s);
      _toast('Added ${s.name}');
    } catch (e) {
      _toast(e.toString());
    } finally {
      api.close();
    }
  }

  Future<void> _offerDownload(String link) async {
    var target = servers.current!;
    final go = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => _Sheet(
          title: 'Download this link?',
          body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(link, maxLines: 3, overflow: TextOverflow.ellipsis),
            if (servers.list.length > 1)
              DropdownButton<String>(
                value: target.url,
                isExpanded: true,
                items: [for (final s in servers.list) DropdownMenuItem(value: s.url, child: Text('on ${s.name}'))],
                onChanged: (u) => set(() => target = servers.list.firstWhere((s) => s.url == u)),
              ),
          ]),
          action: 'Download',
        ),
      ),
    );
    if (go == true) await addDownload(target, link, _toast);
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _addDialog() async {
    final c = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Add download'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'Link, video page or magnet'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Download')),
        ],
      ),
    );
    if (link != null && link.isNotEmpty) await addDownload(servers.current!, link, _toast);
  }

  void _switcher() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in servers.list)
            ListTile(
              leading: Icon(s.url == servers.current!.url ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(s.name),
              subtitle: Text(s.url),
              onTap: () {
                servers.select(s);
                Navigator.pop(c);
              },
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add server'),
            onTap: () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (_) => AddServerScreen(servers: servers)));
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = servers.current!;
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _switcher,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(s.name, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down),
          ]),
        ),
        actions: [
          IconButton(
            tooltip: 'Server settings',
            icon: const Icon(Icons.settings),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => ServerScreen(servers: servers, server: s))),
          ),
        ],
      ),
      body: JobsView(key: ValueKey(s.url), server: s),
      floatingActionButton:
          FloatingActionButton(onPressed: _addDialog, tooltip: 'Add download', child: const Icon(Icons.add)),
    );
  }
}

Future<void> addDownload(Server s, String link, void Function(String) toast) async {
  final api = Api(s);
  try {
    final j = await api.add(link);
    toast('Added to ${s.name}: ${j['name'] ?? link}');
  } catch (e) {
    toast(e.toString());
  } finally {
    api.close();
  }
}

class _Sheet extends StatelessWidget {
  final String title;
  final Widget body;
  final String action;
  const _Sheet({required this.title, required this.body, required this.action});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            body,
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ignore')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
            ]),
          ]),
        ),
      );
}
