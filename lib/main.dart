import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'discover.dart';
import 'files.dart';
import 'jobs.dart';
import 'library.dart';
import 'pair.dart';
import 'phone.dart';
import 'servers.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics(); // screen readers (and browser automation) on web
  // Right click shows our own menus only, not the browser's.
  if (kIsWeb) BrowserContextMenu.disableContextMenu();
  await AppSettings.instance.load();
  final servers = Servers();
  await servers.load();
  runApp(App(servers: servers));
}

class App extends StatelessWidget {
  final Servers servers;
  const App({super.key, required this.servers});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF4F46E5); // indigo
    final s = AppSettings.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (_, _) => MaterialApp(
        title: 'download_me_not',
        theme: _theme(seed, Brightness.light),
        darkTheme: _theme(seed, Brightness.dark),
        themeMode: {'dark': ThemeMode.dark, 'system': ThemeMode.system}[s.theme] ?? ThemeMode.light,
        home: ListenableBuilder(
          listenable: servers,
          builder: (_, _) =>
              servers.current == null ? AddServerScreen(servers: servers, first: true) : Home(servers: servers),
        ),
      ),
    );
  }
}

// Tailwind-style tokens: slate grays, indigo accent, white cards with hairline borders, rounded-lg corners.
class Tw {
  static const slate50 = Color(0xFFF8FAFC), slate100 = Color(0xFFF1F5F9), slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1), slate400 = Color(0xFF94A3B8), slate500 = Color(0xFF64748B);
  static const slate700 = Color(0xFF334155), slate800 = Color(0xFF1E293B), slate900 = Color(0xFF0F172A);
  static const slate950 = Color(0xFF020617);
  static const indigo100 = Color(0xFFE0E7FF), indigo400 = Color(0xFF818CF8), indigo600 = Color(0xFF4F46E5);
  static const indigo900 = Color(0xFF312E81);
  static const emerald100 = Color(0xFFD1FAE5), emerald600 = Color(0xFF059669), emerald800 = Color(0xFF065F46);
  static const red100 = Color(0xFFFEE2E2), red600 = Color(0xFFDC2626), red800 = Color(0xFF991B1B);
}

ThemeData _theme(Color seed, Brightness b) {
  final light = b == Brightness.light;
  final cs = ColorScheme.fromSeed(seedColor: seed, brightness: b).copyWith(
    primary: light ? Tw.indigo600 : Tw.indigo400,
    onPrimary: light ? Colors.white : Tw.slate950,
    primaryContainer: light ? Tw.indigo100 : Tw.indigo900,
    onPrimaryContainer: light ? Tw.indigo900 : Tw.indigo100,
    secondaryContainer: light ? Tw.slate100 : Tw.slate800,
    onSecondaryContainer: light ? Tw.slate900 : Tw.slate100,
    tertiary: Tw.emerald600,
    tertiaryContainer: light ? Tw.emerald100 : Tw.emerald800,
    onTertiaryContainer: light ? Tw.emerald800 : Tw.emerald100,
    error: Tw.red600,
    errorContainer: light ? Tw.red100 : Tw.red800,
    onErrorContainer: light ? Tw.red800 : Tw.red100,
    surface: light ? Colors.white : Tw.slate900,
    onSurface: light ? Tw.slate900 : Tw.slate100,
    onSurfaceVariant: light ? Tw.slate500 : Tw.slate400,
    surfaceContainerLowest: light ? Tw.slate50 : Tw.slate950,
    surfaceContainerLow: light ? Colors.white : Tw.slate900,
    surfaceContainer: light ? Colors.white : Tw.slate900,
    surfaceContainerHigh: light ? Tw.slate100 : Tw.slate800,
    surfaceContainerHighest: light ? Tw.slate200 : Tw.slate700,
    outline: light ? Tw.slate300 : Tw.slate700,
    outlineVariant: light ? Tw.slate200 : Tw.slate800,
  );
  const r8 = BorderRadius.all(Radius.circular(8)), r12 = BorderRadius.all(Radius.circular(12));
  final base = ThemeData(colorScheme: cs);
  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: r8,
    borderSide: BorderSide(color: c, width: w),
  );
  return base.copyWith(
    scaffoldBackgroundColor: cs.surfaceContainerLowest,
    dividerColor: cs.outlineVariant,
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: cs.outlineVariant)),
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: r12,
        side: BorderSide(color: cs.outlineVariant),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: r8,
        side: BorderSide(color: cs.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: const RoundedRectangleBorder(borderRadius: r8)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: r8),
        side: BorderSide(color: cs.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: const RoundedRectangleBorder(borderRadius: r8)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(shape: RoundedRectangleBorder(borderRadius: r12)),
    dialogTheme: DialogThemeData(
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: r12),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: cs.surface, surfaceTintColor: Colors.transparent),
    listTileTheme: const ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: r8)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surface,
      indicatorColor: cs.primaryContainer,
      indicatorShape: const RoundedRectangleBorder(borderRadius: r8),
      labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: field(cs.outline),
      enabledBorder: field(cs.outline),
      focusedBorder: field(cs.primary, 2),
      hintStyle: TextStyle(color: cs.onSurfaceVariant),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: r8)),
        side: WidgetStatePropertyAll(BorderSide(color: cs.outline)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? cs.primaryContainer : null,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? cs.onPrimaryContainer : cs.onSurface,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: r8),
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
  String _addonsChecked = ''; // server whose add-on switch was last fetched

  // Fetches whether add-ons are on for this server (once per server; Settings updates it when toggled).
  void _checkAddons(Server s) {
    if (_addonsChecked == s.url + s.token) return; // again after signing in with a new token
    _addonsChecked = s.url + s.token;
    addonsEnabled.value = false;
    final api = Api(s);
    api
        .call('GET', '/v1/addons')
        .then((a) => addonsEnabled.value = a['enabled'] == true, onError: (_) {})
        .whenComplete(api.close);
  }

  void _onAddons() => mounted ? setState(() {}) : null;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    addonsEnabled.addListener(_onAddons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    addonsEnabled.removeListener(_onAddons);
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
    final ok = await confirm(
      context,
      title: 'Add server ${s.name}?',
      body: Text('The clipboard has a pairing link for ${s.url}.'),
      action: 'Add server',
    );
    if (!ok) return;
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
    final go = await confirm(
      context,
      title: 'Download this link?',
      body: StatefulBuilder(
        builder: (c, set) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(link, maxLines: 3, overflow: TextOverflow.ellipsis),
            if (servers.list.length > 1) ...[
              const SizedBox(height: 12),
              DropdownMenu<String>(
                initialSelection: target.url,
                label: const Text('Server'),
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [for (final s in servers.list) DropdownMenuEntry(value: s.url, label: s.name)],
                onSelected: (u) => set(() => target = servers.list.firstWhere((s) => s.url == u)),
              ),
            ],
          ],
        ),
      ),
      action: 'Download',
    );
    if (go) await addDownload(target, link, _toast);
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // Server switcher: a dropdown menu under the server button.
  void _switcher(Offset at) {
    showContextMenu(context, at, title: 'Servers', [
      for (final s in servers.list)
        MenuAction(s.name, checked: s.url == servers.current!.url, onTap: () => servers.select(s)),
      const MenuAction.divider(),
      MenuAction(
        'Add server…',
        icon: Icons.add,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddServerScreen(servers: servers))),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = servers.current!;
    // Wide (tablet, desktop, web): a website-style header with links. Narrow (phones): a bottom bar.
    final wide = MediaQuery.sizeOf(context).width >= 840;
    _checkAddons(s);
    final discover = addonsEnabled.value; // the Discover tab exists only while add-ons are on
    final dests = [
      (Icons.download_outlined, Icons.download, 'Downloads'),
      (Icons.video_library_outlined, Icons.video_library, 'Media'),
      (Icons.folder_outlined, Icons.folder, 'Files'),
      if (discover) (Icons.explore_outlined, Icons.explore, 'Discover'),
      (Icons.settings_outlined, Icons.settings, 'Settings'),
    ];
    if (_tab >= dests.length) _tab = dests.length - 1;
    final cs = Theme.of(context).colorScheme;
    final serverButton = Builder(
      builder: (b) => TextButton.icon(
        onPressed: () => _switcher(anchorOf(b)),
        icon: const Icon(Icons.dns_outlined, size: 18),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(s.name, overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
        style: TextButton.styleFrom(foregroundColor: cs.onSurface),
      ),
    );
    return Scaffold(
      appBar: wide
          ? AppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: 64,
              titleSpacing: 24,
              title: Row(
                children: [
                  Icon(Icons.downloading, color: cs.primary),
                  const SizedBox(width: 8),
                  const Text('download_me_not'),
                  const SizedBox(width: 32),
                  for (final (i, (_, _, label)) in dests.indexed)
                    _NavLink(label, i == _tab, () => setState(() => _tab = i)),
                ],
              ),
              actions: [serverButton, const SizedBox(width: 16)],
            )
          : AppBar(title: serverButton, titleSpacing: 8),
      body: Column(
        children: [
          // A rejected token: one banner with a way back in, instead of errors on every screen.
          ValueListenableBuilder<String?>(
            valueListenable: Api.unauthorized,
            builder: (_, url, _) => url == s.url ? _ReauthBanner(servers: servers, server: s) : const SizedBox.shrink(),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200), // readable width on big screens, like a website
                child: IndexedStack(
                  index: _tab,
                  children: [
                    DownloadsView(key: ValueKey('jobs${s.url}${s.token.hashCode}'), server: s),
                    MediaView(key: ValueKey('media${s.url}${s.token.hashCode}'), servers: servers, server: s),
                    FilesView(key: ValueKey('files${s.url}${s.token.hashCode}'), server: s),
                    if (discover) DiscoverView(key: ValueKey('disc${s.url}${s.token.hashCode}'), server: s),
                    SettingsView(key: ValueKey('set${s.url}${s.token.hashCode}'), servers: servers, server: s),
                  ],
                ),
              ),
            ),
          ),
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
    );
  }
}

/// The download queue on the server, and (on Android) what was saved to this phone.
class DownloadsView extends StatefulWidget {
  final Server server;
  const DownloadsView({super.key, required this.server});
  @override
  State<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends State<DownloadsView> {
  bool _phone = false;

  @override
  Widget build(BuildContext context) {
    final queue = JobsView(server: widget.server);
    if (!Api.canDownload) return queue;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('On the server'), icon: Icon(Icons.dns_outlined)),
              ButtonSegment(value: true, label: Text('On this phone'), icon: Icon(Icons.phone_android)),
            ],
            selected: {_phone},
            onSelectionChanged: (v) => setState(() => _phone = v.first),
          ),
        ),
        Expanded(
          child: IndexedStack(index: _phone ? 1 : 0, children: [queue, const PhoneView()]),
        ),
      ],
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

/// A header link like on a website: text, with an underline when it is the current page.
class _NavLink extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavLink(this.label, this.active, this.onTap);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: active ? cs.primary : Colors.transparent, width: 2)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the server rejects this device's token (it was replaced or removed on the server). Tokens do not
/// expire, so this is rare; one tap brings the device back with the server's address already filled in.
class _ReauthBanner extends StatelessWidget {
  final Servers servers;
  final Server server;
  const _ReauthBanner({required this.servers, required this.server});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              '${server.name} no longer accepts this device. Sign in again to continue.',
              style: TextStyle(color: cs.onErrorContainer),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddServerScreen(servers: servers, initialUrl: server.url),
                ),
              ),
              child: const Text('Sign in again'),
            ),
          ],
        ),
      ),
    );
  }
}
