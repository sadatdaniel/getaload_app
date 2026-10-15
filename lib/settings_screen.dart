// Settings, GNOME style: a short list of topics, each opening its own page of grouped rows. This device's topics
// first (look, player, downloads), then the person's, then the server's.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'about_app.dart';
import 'api.dart';
import 'server_screen.dart';
import 'servers.dart';
import 'settings.dart';
import 'ui.dart';
import 'users.dart';

class SettingsView extends StatelessWidget {
  final Servers servers;
  final Server server;
  const SettingsView({super.key, required this.servers, required this.server});

  // Opens one topic. The page reads the server from the saved list on every change, so it sees a new sign-in or
  // admin key (e.g. right after getting server control on that page).
  void _open(BuildContext context, String title, Widget Function(Server s) page) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListenableBuilder(
          listenable: servers,
          builder: (context, _) {
            final s = servers.list.where((x) => x.url == server.url).firstOrNull ?? server;
            return Scaffold(
              appBar: AppBar(title: Text(title)),
              body: ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 32),
                children: [KeyedSubtree(key: ValueKey('${s.token.hashCode}${s.adminKey.hashCode}'), child: page(s))],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget local(Widget Function() f) =>
        ListenableBuilder(listenable: AppSettings.instance, builder: (context, _) => f()); // this device's choices
    Widget srv(Server s, String only) => ServerScreen(servers: servers, server: s, only: only);
    final topics = <(String, String, Widget Function(Server))>[
      ('Appearance', 'Light or dark, files as grid or list', (_) => local(_appearance)),
      ('Player', 'Seek step, subtitles, playing the next file', (_) => local(_player)),
      (
        'Downloads',
        'What to ask when adding, site sign-ins, leftover files',
        (s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [local(_adding), srv(s, 'downloads')]),
      ),
      ('Google Drive', 'Your own Drive, for copies of your downloads', (s) => srv(s, 'drive')),
      if (server.user.isNotEmpty) ...[
        (
          'Your devices',
          'Where you are signed in, and your PIN',
          (s) => AccountSettings(servers: servers, server: s, only: 'account'),
        ),
        (
          'Server control',
          'People, updates and add-ons',
          (s) => AccountSettings(servers: servers, server: s, only: 'control'),
        ),
      ],
      ('Server', 'Name, address, version and updates', (s) => srv(s, 'server')),
      ('Network', 'Whether peers can reach the torrent port', (s) => srv(s, 'network')),
      ('Add-ons (experimental)', 'Stremio catalogs and subtitles', (s) => srv(s, 'addons')),
      ('About this app', 'Version and app updates', (_) => const AboutApp()),
    ];
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        SettingsGroup(
          children: [
            for (final (title, sub, page) in topics)
              SettingsRow(title: title, subtitle: sub, onTap: () => _open(context, title, page)),
          ],
        ),
      ],
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
