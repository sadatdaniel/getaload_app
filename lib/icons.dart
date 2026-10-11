// File and folder icons: colored folders with a glyph for what is inside (from the folder name),
// colored tiles for files by type, and small status badges (downloading, partial, in the cloud).
import 'package:flutter/material.dart';

import 'api.dart';

typedef FileStyle = (IconData glyph, Color color);

const _folderStyles = <(List<String>, FileStyle)>[
  (['movie', 'film', 'cinema'], (Icons.movie, Color(0xFF8E7CC3))),
  (['video', 'clip'], (Icons.videocam, Color(0xFF8E7CC3))),
  (['tv', 'show', 'series', 'season', 'episode'], (Icons.tv, Color(0xFF6D8BD6))),
  (['music', 'audio', 'song', 'album', 'mp3', 'flac'], (Icons.headphones, Color(0xFFD9826B))),
  (['podcast'], (Icons.podcasts, Color(0xFFD9826B))),
  (['download', 'incoming', 'torrent'], (Icons.download, Color(0xFF4F8FD6))),
  (['picture', 'photo', 'image', 'dcim', 'camera', 'wallpaper'], (Icons.image, Color(0xFF5BAE7A))),
  (['book', 'comic', 'manga'], (Icons.menu_book, Color(0xFFC49A3D))),
  (['doc', 'pdf', 'paper', 'note'], (Icons.description, Color(0xFF5B9BB0))),
  (['backup', 'archive'], (Icons.backup, Color(0xFF7D8A99))),
  (['game'], (Icons.sports_esports, Color(0xFFCF6D8E))),
  (['app', 'software', 'program', 'apk'], (Icons.apps, Color(0xFF43A6A0))),
];

FileStyle _folderStyle(String name) {
  final n = name.toLowerCase();
  for (final (keys, style) in _folderStyles) {
    if (keys.any(n.contains)) return style;
  }
  return (Icons.circle, const Color(0xFF7FA0C4)); // plain folder; the glyph is not drawn
}

FileStyle fileStyle(FileEntry e) {
  if (e.isVideo) return (Icons.movie_outlined, const Color(0xFF8E7CC3));
  if (e.isAudio) return (Icons.music_note, const Color(0xFFD9826B));
  if (e.isArchive) return (Icons.folder_zip_outlined, const Color(0xFFC49A3D));
  return switch (e.ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' => (Icons.image_outlined, const Color(0xFF5BAE7A)),
    'pdf' => (Icons.picture_as_pdf_outlined, const Color(0xFFD0605E)),
    'srt' || 'vtt' || 'ass' || 'ssa' || 'sub' => (Icons.closed_caption_outlined, const Color(0xFF5B9BB0)),
    'torrent' => (Icons.hub_outlined, const Color(0xFF4F8FD6)),
    'iso' || 'img' => (Icons.album_outlined, const Color(0xFF7D8A99)),
    'apk' => (Icons.android, const Color(0xFF43A6A0)),
    'txt' || 'md' || 'nfo' || 'log' => (Icons.notes, const Color(0xFF7D8A99)),
    'part' => (Icons.hourglass_bottom, const Color(0xFF9AA5B1)),
    _ => (Icons.insert_drive_file_outlined, const Color(0xFF7D8A99)),
  };
}

/// What the server's job list says about a file: still downloading (with progress) and/or copied to a cloud.
class FileStatus {
  final double? progress; // 0..1 while downloading, -1 if unknown; null when complete
  final bool cloud;
  final String? jobId; // the unfinished download, for streaming while it runs
  const FileStatus({this.progress, this.cloud = false, this.jobId});
}

class EntryIcon extends StatelessWidget {
  final FileEntry entry;
  final double size;
  final FileStatus? status;
  const EntryIcon({super.key, required this.entry, this.size = 56, this.status});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Widget base;
    if (entry.dir) {
      final (glyph, color) = _folderStyle(entry.name);
      base = Stack(
        alignment: const Alignment(0, 0.25),
        children: [
          Icon(Icons.folder_rounded, size: size, color: dark ? Color.lerp(color, Colors.black, 0.15) : color),
          if (glyph != Icons.circle) Icon(glyph, size: size * 0.36, color: Colors.white.withValues(alpha: 0.95)),
        ],
      );
    } else {
      final (glyph, color) = fileStyle(entry);
      base = Container(
        width: size * 0.82,
        height: size * 0.92,
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.30 : 0.16),
          borderRadius: BorderRadius.circular(size * 0.18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(glyph, size: size * 0.42, color: color),
            if (entry.ext.isNotEmpty && size >= 48)
              Text(
                entry.ext.toUpperCase(),
                style: TextStyle(fontSize: size * 0.15, fontWeight: FontWeight.w700, color: color),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
          ],
        ),
      );
    }
    final s = status;
    final partial = entry.ext == 'part';
    if (s == null && !partial) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: base),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: base),
          if (s?.progress != null || partial)
            Positioned(
              right: -2,
              bottom: -2,
              child: _Badge(
                tooltip: 'Not complete',
                child: SizedBox(
                  width: size * 0.26,
                  height: size * 0.26,
                  // Known progress: a ring that fills. Unknown (a leftover .part, a queued job): a static mark,
                  // since a spinner would claim something is happening.
                  child: (s?.progress ?? -1) >= 0
                      ? CircularProgressIndicator(
                          value: s!.progress,
                          strokeWidth: 2.5,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        )
                      : Icon(Icons.downloading, size: size * 0.26, color: Theme.of(context).colorScheme.tertiary),
                ),
              ),
            ),
          if (s?.cloud == true)
            Positioned(
              right: -2,
              top: -2,
              child: _Badge(
                tooltip: 'Copied to the cloud',
                child: Icon(Icons.cloud_done, size: size * 0.26, color: Theme.of(context).colorScheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final Widget child;
  final String tooltip;
  const _Badge({required this.child, required this.tooltip});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
      child: child,
    ),
  );
}
