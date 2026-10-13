// The choices for a video page before it downloads (like Seal or NewPipe): video or audio, quality, container,
// audio format and subtitles. Built from the server's /v1/probe answer; the last choices are remembered.
import 'package:flutter/material.dart';

import 'jobs.dart' show fmtBytes;
import 'settings.dart';
import 'ui.dart';

/// Rough size of a quality: the largest video-only stream at or below [maxHeight] plus the largest audio stream.
/// 0 when the site gives no sizes.
int estimateSize(List<Map<String, dynamic>> formats, int? maxHeight, {bool audioOnly = false}) {
  int best(bool Function(Map<String, dynamic>) ok) =>
      formats.where(ok).fold(0, (m, f) => ((f['size'] ?? 0) as int) > m ? f['size'] as int : m);
  final audio = best((f) => f['vcodec'] == 'none' && f['acodec'] != null && f['acodec'] != 'none');
  if (audioOnly) return audio;
  final video = best(
    (f) =>
        f['vcodec'] != null && f['vcodec'] != 'none' && (maxHeight == null || ((f['height'] ?? 0) as int) <= maxHeight),
  );
  return video == 0 ? 0 : video + audio;
}

/// The extra POST /v1/jobs fields the user picked ({format, container, subs}), or null when cancelled.
Future<Map<String, dynamic>?> askVideoOptions(BuildContext context, Map<String, dynamic> media) {
  final s = AppSettings.instance;
  final d = s.videoDefaults;
  final formats = ((media['formats'] as List?) ?? []).cast<Map<String, dynamic>>();
  final subtitles = ((media['subtitles'] as List?) ?? []).cast<String>();
  final top = formats.fold<int>(0, (m, f) => ((f['height'] ?? 0) as int) > m ? f['height'] as int : m);
  // Only qualities the video has (plus Best); a 720p video offers Best and 720p, 480p.
  final qualities = [
    ('best', 'Best', null),
    for (final h in [1080, 720, 480])
      if (top == 0 || h <= top) ('${h}p', '${h}p', h),
  ];
  var audio = d['audio'] == true;
  var quality = qualities.any((q) => q.$1 == d['quality']) ? d['quality'] as String : 'best';
  var container = d['container'] == 'mkv' ? 'mkv' : 'mp4';
  var audioFormat = ['m4a', 'opus', 'mp3'].contains(d['audioFormat']) ? d['audioFormat'] as String : 'm4a';
  final subs = {
    for (final l in (d['subs'] as List? ?? []).cast<String>())
      if (subtitles.contains(l)) l,
  };
  var ask = s.videoAsk;

  String label(String name, int? h) {
    final size = estimateSize(formats, h);
    return size > 0 ? '$name · ≈${fmtBytes(size)}' : name;
  }

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        );
        final dur = (media['duration'] as num?)?.round() ?? 0;
        return AlertDialog(
          title: Text(media['title'] ?? 'Video', maxLines: 2, overflow: TextOverflow.ellipsis),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (dur > 0 || media['extractor'] != null)
                    Text(
                      [
                        if (media['extractor'] != null) media['extractor'],
                        if (dur > 0) '${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')}',
                      ].join(' · '),
                      style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
                    ),
                  section(
                    'Download',
                    Choice<bool>(
                      options: const [(false, 'Video'), (true, 'Audio only')],
                      value: audio,
                      onChanged: (v) => set(() => audio = v),
                    ),
                  ),
                  if (!audio) ...[
                    section(
                      'Quality',
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (v, name, h) in qualities)
                            ChoiceChip(
                              label: Text(label(name, h)),
                              selected: quality == v,
                              showCheckmark: false,
                              onSelected: (_) => set(() => quality = v),
                            ),
                        ],
                      ),
                    ),
                    section(
                      'Format',
                      Choice<String>(
                        options: const [('mp4', 'MP4 (plays everywhere)'), ('mkv', 'MKV')],
                        value: container,
                        onChanged: (v) => set(() => container = v),
                      ),
                    ),
                    section(
                      'Subtitles',
                      subtitles.isEmpty
                          ? const Text('This video has none.')
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final l in subtitles)
                                  FilterChip(
                                    label: Text(l),
                                    selected: subs.contains(l),
                                    onSelected: (on) => set(() => on ? subs.add(l) : subs.remove(l)),
                                  ),
                              ],
                            ),
                    ),
                  ] else
                    section(
                      'Audio format',
                      Choice<String>(
                        options: const [('m4a', 'M4A'), ('opus', 'Opus'), ('mp3', 'MP3')],
                        value: audioFormat,
                        onChanged: (v) => set(() => audioFormat = v),
                      ),
                    ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: !ask,
                    onChanged: (v) => set(() => ask = v != true),
                    title: const Text('Don\'t ask again (use these choices)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                s.videoDefaults = {
                  'audio': audio,
                  'quality': quality,
                  'container': container,
                  'audioFormat': audioFormat,
                  'subs': subs.toList(),
                };
                s.videoAsk = ask;
                Navigator.pop(c, videoRequest(s.videoDefaults));
              },
              child: const Text('Download'),
            ),
          ],
        );
      },
    ),
  );
}

/// The POST /v1/jobs fields for remembered choices (used directly when the dialog is switched off).
Map<String, dynamic> videoRequest(Map<String, dynamic> d) => d['audio'] == true
    ? {'format': d['audioFormat'] ?? 'm4a'}
    : {
        'format': d['quality'] ?? 'best',
        'container': d['container'] ?? 'mp4',
        if ((d['subs'] as List? ?? []).isNotEmpty) 'subs': d['subs'],
      };
