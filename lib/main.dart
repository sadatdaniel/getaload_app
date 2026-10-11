import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'files.dart';
import 'jobs.dart';
import 'pair.dart';
import 'phone.dart';
import 'server_screen.dart';
import 'servers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics(); // screen readers (and browser automation) on web
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
      theme: _theme(seed, Brightness.light),
      darkTheme: _theme(seed, Brightness.dark),
      home: ListenableBuilder(
        listenable: servers,
        builder: (_, _) =>
            servers.current == null ? AddServerScreen(servers: servers, first: true) : Home(servers: servers),
      ),
    );
  }
}

// Material 3 with the expressive color scheme and rounder shapes (Flutter has no M3 Expressive components yet).
ThemeData _theme(Color seed, Brightness b) {
  final cs = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: b,
    dynamicSchemeVariant: DynamicSchemeVariant.expressive,
  );
  return ThemeData(
    colorScheme: cs,
    cardTheme: const CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24)))),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(shape: StadiumBorder()),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorShape: const StadiumBorder(),
      backgroundColor: cs.surfaceContainer,
    ),
  );
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
  int _tab = 0;

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
      String text;
      try {
        text = ((await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '').trim();
      } catch (_) {
        return; // the browser denied clipboard access, or nothing readable is there
      }
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
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(link, maxLines: 3, overflow: TextOverflow.ellipsis),
              if (servers.list.length > 1)
                DropdownButton<String>(
                  value: target.url,
                  isExpanded: true,
                  items: [for (final s in servers.list) DropdownMenuItem(value: s.url, child: Text('on ${s.name}'))],
                  onChanged: (u) => set(() => target = servers.list.firstWhere((s) => s.url == u)),
                ),
            ],
          ),
          action: 'Download',
        ),
      ),
    );
    if (go == true) await addDownload(target, link, _toast);
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _switcher() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = servers.current!;
    final wide = MediaQuery.sizeOf(context).width >= 840; // Material's expanded window class
    final queue = JobsView(key: ValueKey('jobs${s.url}'), server: s);
    final dests = [
      (Icons.folder_outlined, Icons.folder, 'Files'),
      if (Api.canDownload) (Icons.phone_android_outlined, Icons.phone_android, 'Phone'),
      (Icons.dns_outlined, Icons.dns, 'Server'),
    ];
    if (_tab >= dests.length) _tab = 0;
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _switcher,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(s.name, overflow: TextOverflow.ellipsis)),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          if (!wide)
            Builder(
              builder: (c) => IconButton(
                tooltip: 'Downloads',
                icon: const Icon(Icons.downloading),
                onPressed: () => Scaffold.of(c).openEndDrawer(),
              ),
            ),
        ],
      ),
      // Phones: the queue is a drawer. Tablets and desktop: a rail on the left and the queue always on the right.
      endDrawer: wide
          ? null
          : Drawer(
              width: min(400, MediaQuery.sizeOf(context).width * 0.88),
              child: SafeArea(child: queue),
            ),
      body: Row(
        children: [
          if (wide) ...[
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (icon, sel, label) in dests)
                  NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: Text(label)),
              ],
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                FilesView(key: ValueKey('files${s.url}'), server: s),
                if (Api.canDownload) const PhoneView(),
                ServerScreen(key: ValueKey('srv${s.url}'), servers: servers, server: s),
              ],
            ),
          ),
          if (wide) ...[const VerticalDivider(width: 1), SizedBox(width: 400, child: queue)],
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                for (final (icon, sel, label) in dests)
                  NavigationDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: label),
              ],
            ),
      floatingActionButton: wide || _tab != 0
          ? null
          : Builder(
              builder: (c) => FloatingActionButton.extended(
                onPressed: () => Scaffold.of(c).openEndDrawer(),
                icon: const Icon(Icons.add),
                label: const Text('Download'),
              ),
            ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          body,
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ignore')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
            ],
          ),
        ],
      ),
    ),
  );
}
