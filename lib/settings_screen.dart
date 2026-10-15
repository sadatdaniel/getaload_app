// Settings, GNOME style: a short list of topics, each with its own page of grouped rows. Wide screens show the topics
// in a sidebar and the chosen page beside it (like GNOME Settings); phones show the list and open a page on tap.
// This device's topics first (look, player, downloads), then the person's, then the server's.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'about_app.dart';
import 'api.dart';
import 'server_screen.dart';
import 'servers.dart';
import 'settings.dart';
import 'ui.dart';
import 'users.dart';

// The topic shown on wide screens. Kept outside the widget: Settings is rebuilt when the sign-in or admin key changes
// (e.g. right after getting server control), and must stay on the same page.
String _topic = 'Appearance';

typedef _Topic = ({String title, String sub, IconData icon, int group, Widget Function(Server) page});

class SettingsView extends StatefulWidget {
  final Servers servers;
  final Server server;
  const SettingsView({super.key, required this.servers, required this.server});
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  Servers get servers => widget.servers;

  // The server as saved now, so a page sees a new sign-in or admin key without being opened again.
  Server get _current => servers.list.where((x) => x.url == widget.server.url).firstOrNull ?? widget.server;

  Widget _page(_Topic t) => ListenableBuilder(
    listenable: servers,
    builder: (context, _) {
      final s = _current;
      return KeyedSubtree(key: ValueKey('${t.title}${s.token.hashCode}${s.adminKey.hashCode}'), child: t.page(s));
    },
  );

  List<_Topic> get _topics {
    Widget local(Widget Function() f) =>
        ListenableBuilder(listenable: AppSettings.instance, builder: (context, _) => f()); // this device's choices
    Widget srv(Server s, String only) => ServerScreen(servers: servers, server: s, only: only);
    Widget acc(Server s, String only) => AccountSettings(servers: servers, server: s, only: only);
    return [
      (
        title: 'Appearance',
        sub: 'Light or dark, files as grid or list',
        icon: Icons.palette_outlined,
        group: 0,
        page: (_) => local(_appearance),
      ),
      (
        title: 'Player',
        sub: 'Seek step, subtitles, playing the next file',
        icon: Icons.play_circle_outline,
        group: 0,
        page: (_) => local(_player),
      ),
      (
        title: 'Downloads',
        sub: 'What to ask when adding, site sign-ins, leftover files',
        icon: Icons.download_outlined,
        group: 0,
        page: (s) =>
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [local(_adding), srv(s, 'downloads')]),
      ),
      (
        title: 'Google Drive',
        sub: 'Your own Drive, for copies of your downloads',
        icon: Icons.add_to_drive,
        group: 1,
        page: (s) => srv(s, 'drive'),
      ),
      if (widget.server.user.isNotEmpty) ...[
        (
          title: 'Your devices',
          sub: 'Where you are signed in, and your PIN',
          icon: Icons.devices_outlined,
          group: 1,
          page: (s) => acc(s, 'account'),
        ),
        (
          title: 'Server control',
          sub: 'People, updates and add-ons',
          icon: Icons.admin_panel_settings_outlined,
          group: 1,
          page: (s) => acc(s, 'control'),
        ),
      ],
      (
        title: 'Server',
        sub: 'Name, address, version and updates',
        icon: Icons.dns_outlined,
        group: 2,
        page: (s) => srv(s, 'server'),
      ),
      (
        title: 'Network',
        sub: 'Whether peers can reach the torrent port',
        icon: Icons.lan_outlined,
        group: 2,
        page: (s) => srv(s, 'network'),
      ),
      (
        title: 'Add-ons (experimental)',
        sub: 'Stremio catalogs and subtitles',
        icon: Icons.extension_outlined,
        group: 2,
        page: (s) => srv(s, 'addons'),
      ),
      (
        title: 'About this app',
        sub: 'Version and app updates',
        icon: Icons.info_outline,
        group: 2,
        page: (_) => const AboutApp(),
      ),
    ];
  }

  // Phones: the topic opens as its own page with a back arrow.
  void _open(_Topic t) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(t.title)),
        body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 32), children: [_page(t)]),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final topics = _topics;
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 840) {
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              SettingsGroup(
                children: [for (final t in topics) SettingsRow(title: t.title, subtitle: t.sub, onTap: () => _open(t))],
              ),
            ],
          );
        }
        final shown = topics.where((t) => t.title == _topic).firstOrNull ?? topics.first;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 260, child: _sidebar(topics, shown)),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 16, bottom: 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_page(shown)]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // GNOME-like sidebar: icon and title per topic, the chosen one highlighted, groups separated by a line.
  Widget _sidebar(List<_Topic> topics, _Topic shown) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final (i, t) in topics.indexed) ...[
            if (i > 0 && topics[i - 1].group != t.group) const Divider(height: 17, indent: 8, endIndent: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Material(
                color: t.title == shown.title ? cs.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _topic = t.title),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(t.icon, size: 20, color: cs.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(child: Text(t.title, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _slider(double v, double min, double max, int div, ValueChanged<double> f) => SizedBox(
  width: 220,
  child: Slider(value: v.clamp(min, max), min: min, max: max, divisions: div, onChanged: f),
);

Widget _appearance() {
  final s = AppSettings.instance;
  return SettingsGroup(
    title: 'Appearance',
    children: [
      SettingsRow(
        title: 'Style',
        trailing: Choice<String>(
          options: const [('light', 'Light'), ('dark', 'Dark'), ('system', 'System')],
          value: s.theme,
          onChanged: (v) => s.theme = v,
        ),
      ),
      SettingsRow(
        title: 'Show files as',
        trailing: Choice<bool>(
          options: const [(true, 'Grid'), (false, 'List')],
          value: s.filesGrid,
          onChanged: (v) => s.filesGrid = v,
        ),
      ),
    ],
  );
}

Widget _player() {
  final s = AppSettings.instance;
  return SettingsGroup(
    title: 'Player',
    description: 'Settings for this device.',
    children: [
      // The browser's own player has no buffer or decoder options; those are mpv's.
      if (!kIsWeb) ...[
        SettingsRow(
          title: 'Buffer',
          subtitle: '${s.bufferMiB} MiB of memory for reading ahead',
          trailing: _slider(s.bufferMiB.toDouble(), 16, 512, 31, (v) => s.bufferMiB = v.round()),
        ),
        SettingsRow(
          title: 'Read ahead',
          subtitle: '${s.readaheadSecs} seconds',
          trailing: _slider(s.readaheadSecs.toDouble(), 10, 300, 29, (v) => s.readaheadSecs = v.round()),
        ),
      ],
      SettingsRow(
        title: 'Seek step',
        trailing: Choice<int>(
          options: const [(5, '5 s'), (10, '10 s'), (15, '15 s'), (30, '30 s')],
          value: s.seekStep,
          onChanged: (v) => s.seekStep = v,
        ),
      ),
      if (!kIsWeb)
        SettingsRow(
          title: 'Decoder',
          subtitle:
              'Hardware saves battery. Compatible also uses the hardware but works around a green, black '
              'or broken picture on some phones. Software plays everything, using more battery.',
          trailing: Choice<String>(
            options: const [('auto-safe', 'Hardware'), ('auto-copy', 'Compatible'), ('no', 'Software')],
            value: s.hwdec,
            onChanged: (v) => s.hwdec = v,
          ),
        ),
      SettingsRow(
        title: 'Subtitle size',
        subtitle: '${(s.subtitleScale * 100).round()}%',
        trailing: _slider(s.subtitleScale, 0.5, 3, 25, (v) => s.subtitleScale = v),
      ),
      SettingsRow(
        title: 'Play the next file in the folder',
        subtitle: 'When a video ends, continue with the next one.',
        trailing: Switch(value: s.autoplayNext, onChanged: (v) => s.autoplayNext = v),
      ),
    ],
  );
}

Widget _adding() {
  final s = AppSettings.instance;
  return SettingsGroup(
    title: 'Adding downloads',
    children: [
      SettingsRow(
        title: 'Ask for video options',
        subtitle: 'Video or audio, quality, format and subtitles when a video page is added.',
        trailing: Switch(value: s.videoAsk, onChanged: (v) => s.videoAsk = v),
      ),
      SettingsRow(
        title: 'Ask for torrent options',
        subtitle: 'Stream, unpack and Drive options when torrents are added.',
        trailing: Switch(value: s.torrentAsk, onChanged: (v) => s.torrentAsk = v),
      ),
    ],
  );
}
