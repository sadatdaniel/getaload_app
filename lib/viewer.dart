// Built-in viewers for server files: text (notes, logs, subtitles, nfo…), PDF and images, in a window.
// Loaded as a deferred library (PDF support is large), so it costs nothing until a file is opened.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'api.dart';
import 'jobs.dart' show fmtBytes;

const textExts = FileEntry.textExts, imageExts = FileEntry.imageExts;

/// Larger files are offered for download instead of being loaded into memory.
const maxViewBytes = 64 << 20;

/// Opens [e] in a window: a large dialog on wide screens, full screen on phones.
Future<void> openViewer(BuildContext context, Api api, FileEntry e) {
  final wide = MediaQuery.sizeOf(context).width >= 840;
  final child = _Viewer(api: api, entry: e);
  return showDialog(
    context: context,
    builder: (c) => wide
        ? Dialog(
            insetPadding: const EdgeInsets.all(32),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: child),
          )
        : Dialog.fullscreen(child: child),
  );
}

class _Viewer extends StatefulWidget {
  final Api api;
  final FileEntry entry;
  const _Viewer({required this.api, required this.entry});
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final Future<List<int>> _data = widget.entry.size > maxViewBytes
      ? Future.error('This file is ${fmtBytes(widget.entry.size)}; download it to open it.')
      : widget.api.fileBytes(widget.entry);
  bool _wrap = true;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: cs.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (textExts.contains(e.ext))
                  IconButton(
                    tooltip: _wrap ? 'Don\'t wrap lines' : 'Wrap lines',
                    icon: Icon(_wrap ? Icons.wrap_text : Icons.notes),
                    onPressed: () => setState(() => _wrap = !_wrap),
                  ),
                IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: FutureBuilder<List<int>>(
            future: _data,
            builder: (c, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}')),
                );
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final bytes = snap.data!;
              if (e.ext == 'pdf') {
                return PdfViewer.data(Uint8List.fromList(bytes), sourceName: e.name);
              }
              if (imageExts.contains(e.ext)) {
                return InteractiveViewer(
                  maxScale: 8,
                  child: Center(child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain)),
                );
              }
              final text = utf8.decode(bytes, allowMalformed: true);
              final body = SelectableText(
                text,
                style: TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.45, color: cs.onSurface),
              );
              return Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _wrap ? body : SingleChildScrollView(scrollDirection: Axis.horizontal, child: body),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
