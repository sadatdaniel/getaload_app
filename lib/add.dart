// Adding downloads: links (one or many, pasted together), and .torrent files picked or dropped (one or many).
// Torrents get an options dialog (stream, unpack, Drive, seeding) with "Don't ask again".
import 'dart:convert';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'settings.dart';
import 'ui.dart';

/// Options sent with each torrent (and saved as the default when "Don't ask again" is ticked).
class AddOptions {
  bool stream, extract, drive, deleteLocal, stopSeeding;
  AddOptions({
    this.stream = false,
    this.extract = false,
    this.drive = false,
    this.deleteLocal = false,
    this.stopSeeding = false,
  });

  Map<String, dynamic> toJson() => {
    'stream': stream,
    'extract': extract,
    'drive': drive,
    'deleteLocal': deleteLocal,
    'stopSeeding': stopSeeding,
  };
  factory AddOptions.fromJson(Map<String, dynamic> j) => AddOptions(
    stream: j['stream'] ?? false,
    extract: j['extract'] ?? false,
    drive: j['drive'] ?? false,
    deleteLocal: j['deleteLocal'] ?? false,
    stopSeeding: j['stopSeeding'] ?? false,
  );

  /// Fields of the server's AddRequest.
  Map<String, dynamic> request() => {
    if (stream) 'mode': 'stream',
    if (extract || drive) 'post': {'extract': extract, 'drive': drive, 'deleteLocal': drive && deleteLocal},
    if (stopSeeding) 'seed': {'policy': 'stop'},
  };
}

/// Splits pasted text into links: one per line or separated by spaces.
List<String> splitLinks(String text) =>
    text.split(RegExp(r'\s+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

class AddPanel extends StatefulWidget {
  final Api api;
  final VoidCallback onAdded;
  const AddPanel({super.key, required this.api, required this.onAdded});
  @override
  State<AddPanel> createState() => AddPanelState();
}

class AddPanelState extends State<AddPanel> {
  final _link = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Sends one request per item and reports one summary, so a bulk add never ends in a wall of errors.
  Future<void> _send(List<Map<String, dynamic>> bodies, String what) async {
    if (bodies.isEmpty) return;
    setState(() => _busy = true);
    var ok = 0;
    final failed = <String>[];
    for (final b in bodies) {
      try {
        await widget.api.call('POST', '/v1/jobs', b);
        ok++;
      } catch (e) {
        failed.add(e.toString());
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onAdded();
    if (failed.isEmpty) {
      _toast(ok == 1 ? 'Added' : 'Added $ok $what');
    } else {
      _toast('Added $ok of ${bodies.length}. ${failed.length} failed: ${failed.first}');
    }
  }

  Future<void> _addLinks() async {
    final links = splitLinks(_link.text);
    if (links.isEmpty) return;
    await _send([
      for (final l in links) {'source': l},
    ], 'links');
    _link.clear();
  }

  /// Entry point for torrents from the picker, a drop, or the share sheet later.
  Future<void> addTorrents(List<(String, Uint8List)> files) async {
    final ts = files.where((f) => f.$1.toLowerCase().endsWith('.torrent') && f.$2.isNotEmpty).toList();
    if (ts.isEmpty) {
      _toast('Only .torrent files can be added here. Links go in the box above.');
      return;
    }
    final s = AppSettings.instance;
    var opts = AddOptions.fromJson(s.torrentDefaults);
    if (s.torrentAsk) {
      final picked = await showDialog<AddOptions>(
        context: context,
        builder: (_) => _TorrentDialog(names: [for (final t in ts) t.$1], initial: opts),
      );
      if (picked == null) return;
      opts = picked;
    }
    await _send([
      for (final (_, bytes) in ts) {'torrent': base64Encode(bytes), ...opts.request()},
    ], 'torrents');
  }

  Future<void> _browse() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['torrent'],
    ); // pickFiles allows several; pickFile is the single one
    if (picked.isEmpty) return;
    await addTorrents([for (final f in picked) (f.name, await f.readAsBytes())]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a download', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              'A link, a video page or a magnet. Paste several at once, one per line.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FieldWithButton(
              field: TextField(
                controller: _link,
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(hintText: 'Paste a link or magnet', prefixIcon: Icon(Icons.link)),
                onSubmitted: (_) => _addLinks(),
              ),
              button: FilledButton.icon(
                onPressed: _busy ? null : _addLinks,
                icon: const Icon(Icons.download),
                label: const Text('Download'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              ),
            ),
            const SizedBox(height: 12),
            _DropZone(onTap: _busy ? null : _browse, busy: _busy),
          ],
        ),
      ),
    );
  }
}

class _DropZone extends StatelessWidget {
  final VoidCallback? onTap;
  final bool busy;
  const _DropZone({required this.onTap, required this.busy});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(
        painter: _Dashed(cs.outlineVariant),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.upload_file, color: cs.primary),
              const SizedBox(width: 10),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Drop .torrent files anywhere here, or '),
                      TextSpan(
                        text: 'browse',
                        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dashed extends CustomPainter {
  final Color color;
  _Dashed(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}

class _TorrentDialog extends StatefulWidget {
  final List<String> names;
  final AddOptions initial;
  const _TorrentDialog({required this.names, required this.initial});
  @override
  State<_TorrentDialog> createState() => _TorrentDialogState();
}

class _TorrentDialogState extends State<_TorrentDialog> {
  late final AddOptions o = AddOptions.fromJson(widget.initial.toJson());
  bool _dontAsk = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.names.length;
    final tt = Theme.of(context).textTheme;
    Widget sw(String title, String sub, bool v, ValueChanged<bool> f) => SwitchListTile(
      title: Text(title),
      subtitle: Text(sub),
      value: v,
      onChanged: (x) => setState(() => f(x)),
      dense: true,
    );
    return AlertDialog(
      title: Text(n == 1 ? 'Add this torrent?' : 'Add $n torrents?'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 140),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final name in widget.names)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.hub_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 24),
              sw('Play while downloading', 'Fetch pieces in order (stream mode)', o.stream, (v) => o.stream = v),
              sw('Unpack archives', 'Extract zip/rar/7z when done', o.extract, (v) => o.extract = v),
              sw('Copy to Google Drive', 'Upload when done', o.drive, (v) => o.drive = v),
              if (o.drive)
                sw(
                  'Then delete from the server',
                  'Only after the upload is verified',
                  o.deleteLocal,
                  (v) => o.deleteLocal = v,
                ),
              sw(
                'Stop seeding when done',
                'Otherwise the server\'s seeding policy applies',
                o.stopSeeding,
                (v) => o.stopSeeding = v,
              ),
              CheckboxListTile(
                value: _dontAsk,
                onChanged: (v) => setState(() => _dontAsk = v ?? false),
                title: const Text("Don't ask again"),
                subtitle: const Text('Use these options next time. You can change this in Settings.'),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final s = AppSettings.instance;
            s.torrentDefaults = o.toJson();
            if (_dontAsk) s.torrentAsk = false;
            Navigator.pop(context, o);
          },
          child: Text(n == 1 ? 'Download' : 'Download all ($n)'),
        ),
      ],
    );
  }
}

/// Wraps a screen so .torrent files dropped anywhere on it are added (web and desktop).
class TorrentDropTarget extends StatefulWidget {
  final Widget child;
  final GlobalKey<AddPanelState> panel;
  const TorrentDropTarget({super.key, required this.child, required this.panel});
  @override
  State<TorrentDropTarget> createState() => _TorrentDropTargetState();
}

class _TorrentDropTargetState extends State<TorrentDropTarget> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (d) async {
        setState(() => _over = false);
        final files = [for (final f in d.files) (f.name, await f.readAsBytes())];
        await widget.panel.currentState?.addTorrents(files);
      },
      child: Stack(
        children: [
          widget.child,
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    border: Border.all(color: cs.primary, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      'Drop to add',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: cs.primary),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
