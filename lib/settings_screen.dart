// Settings: this app (player, buffering) and the selected server.
import 'package:flutter/material.dart';

import 'api.dart';
import 'server_screen.dart';
import 'servers.dart';
import 'settings.dart';

class SettingsView extends StatelessWidget {
  final Servers servers;
  final Server server;
  const SettingsView({super.key, required this.servers, required this.server});

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final head = Theme.of(context).textTheme.titleMedium;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('This device', style: head),
        ),
        ListenableBuilder(
          listenable: s,
          builder: (context, _) => Column(
            children: [
              ListTile(
                title: const Text('Theme'),
                subtitle: Wrap(
                  spacing: 8,
                  children: [
                    for (final (v, l) in [('light', 'Light'), ('dark', 'Dark'), ('system', 'Like the phone')])
                      ChoiceChip(label: Text(l), selected: s.theme == v, onSelected: (_) => s.theme = v),
                  ],
                ),
              ),
              ListTile(
                title: const Text('Buffer'),
                subtitle: Slider(
                  value: s.bufferMiB.toDouble(),
                  min: 16,
                  max: 512,
                  divisions: 31,
                  label: '${s.bufferMiB} MiB',
                  onChanged: (v) => s.bufferMiB = v.round(),
                ),
                trailing: Text('${s.bufferMiB} MiB'),
              ),
              ListTile(
                title: const Text('Read ahead'),
                subtitle: Slider(
                  value: s.readaheadSecs.toDouble(),
                  min: 10,
                  max: 300,
                  divisions: 29,
                  label: '${s.readaheadSecs} s',
                  onChanged: (v) => s.readaheadSecs = v.round(),
                ),
                trailing: Text('${s.readaheadSecs} s'),
              ),
              ListTile(
                title: const Text('Seek step'),
                subtitle: Wrap(
                  spacing: 8,
                  children: [
                    for (final v in [5, 10, 15, 30])
                      ChoiceChip(label: Text('$v s'), selected: s.seekStep == v, onSelected: (_) => s.seekStep = v),
                  ],
                ),
              ),
              ListTile(
                title: const Text('Decoder'),
                subtitle: Wrap(
                  spacing: 8,
                  children: [
                    for (final (v, l) in [
                      ('auto-safe', 'Hardware'),
                      ('auto-copy', 'Hardware (copy)'),
                      ('no', 'Software'),
                    ])
                      ChoiceChip(label: Text(l), selected: s.hwdec == v, onSelected: (_) => s.hwdec = v),
                  ],
                ),
              ),
              ListTile(
                title: const Text('Subtitle size'),
                subtitle: Slider(
                  value: s.subtitleScale,
                  min: 0.5,
                  max: 3,
                  divisions: 25,
                  label: '${(s.subtitleScale * 100).round()}%',
                  onChanged: (v) => s.subtitleScale = v,
                ),
                trailing: Text('${(s.subtitleScale * 100).round()}%'),
              ),
              ListTile(
                title: const Text('Preferred languages'),
                subtitle: TextFormField(
                  initialValue: s.preferredLanguages,
                  decoration: const InputDecoration(hintText: 'en,de (audio and subtitles, in order)'),
                  onFieldSubmitted: (v) => s.preferredLanguages = v.trim(),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('Server: ${server.name}', style: head),
        ),
        ServerScreen(key: ValueKey('srv${server.url}'), servers: servers, server: server),
      ],
    );
  }
}
