// Settings, GNOME style: grouped panels of rows. This device first (look, player, adding torrents), then the server.
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    Widget slider(double v, double min, double max, int div, ValueChanged<double> f) => SizedBox(
      width: 220,
      child: Slider(value: v.clamp(min, max), min: min, max: max, divisions: div, onChanged: f),
    );
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        ListenableBuilder(
          listenable: s,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGroup(
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
              ),
              SettingsGroup(
                title: 'Player',
                description: 'Settings for this device.',
                children: [
                  SettingsRow(
                    title: 'Buffer',
                    subtitle: '${s.bufferMiB} MiB of memory for reading ahead',
                    trailing: slider(s.bufferMiB.toDouble(), 16, 512, 31, (v) => s.bufferMiB = v.round()),
                  ),
                  SettingsRow(
                    title: 'Read ahead',
                    subtitle: '${s.readaheadSecs} seconds',
                    trailing: slider(s.readaheadSecs.toDouble(), 10, 300, 29, (v) => s.readaheadSecs = v.round()),
                  ),
                  SettingsRow(
                    title: 'Seek step',
                    trailing: Choice<int>(
                      options: const [(5, '5 s'), (10, '10 s'), (15, '15 s'), (30, '30 s')],
                      value: s.seekStep,
                      onChanged: (v) => s.seekStep = v,
                    ),
                  ),
                  SettingsRow(
                    title: 'Decoder',
                    subtitle: 'Software decoding plays more formats but uses more battery.',
                    trailing: Choice<String>(
                      options: const [('auto-safe', 'Hardware'), ('auto-copy', 'Copy'), ('no', 'Software')],
                      value: s.hwdec,
                      onChanged: (v) => s.hwdec = v,
                    ),
                  ),
                  SettingsRow(
                    title: 'Subtitle size',
                    subtitle: '${(s.subtitleScale * 100).round()}%',
                    trailing: slider(s.subtitleScale, 0.5, 3, 25, (v) => s.subtitleScale = v),
                  ),
                  SettingsRow(
                    title: 'Play the next file in the folder',
                    subtitle: 'When a video ends, continue with the next one.',
                    trailing: Switch(value: s.autoplayNext, onChanged: (v) => s.autoplayNext = v),
                  ),
                  SettingsRow(
                    title: 'Preferred languages',
                    subtitle: 'Audio and subtitles, in order, e.g. en,de',
                    trailing: SizedBox(
                      width: 160,
                      child: TextFormField(
                        initialValue: s.preferredLanguages,
                        onFieldSubmitted: (v) => s.preferredLanguages = v.trim(),
                      ),
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Adding torrents',
                children: [
                  SettingsRow(
                    title: 'Ask for options',
                    subtitle: 'Show stream, unpack and Drive options when torrents are added.',
                    trailing: Switch(value: s.torrentAsk, onChanged: (v) => s.torrentAsk = v),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (server.user.isNotEmpty)
          AccountSettings(key: ValueKey('acc${server.url}${server.token}'), servers: servers, server: server),
        ServerScreen(key: ValueKey('srv${server.url}'), servers: servers, server: server),
      ],
    );
  }
}
