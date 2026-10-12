// The video player (media_kit / libmpv). Plays any Playable: server files through the local pinning proxy,
// files on the phone, and later plugin streams.
import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide Playable, Playlist;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import 'media.dart';
import 'proxy.dart' if (dart.library.js_interop) 'proxy_web.dart';
import 'settings.dart';

bool _mediaKitReady = false;

Future<void> play(BuildContext context, Playable item, {Playlist? list}) {
  if (!_mediaKitReady) {
    MediaKit.ensureInitialized(); // here, not in main(), so the player stays out of the first download
    _mediaKitReady = true;
  }
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlayerScreen(item: item, list: list),
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  final Playable item;
  final Playlist? list; // the rest of the folder, for previous/next
  const PlayerScreen({super.key, required this.item, this.list});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _s = AppSettings.instance;
  late final _player = Player(
    configuration: PlayerConfiguration(bufferSize: _s.bufferMiB << 20, title: widget.item.title),
  );
  late final _video = VideoController(
    _player,
    configuration: VideoControllerConfiguration(hwdec: _s.hwdec, enableHardwareAcceleration: _s.hwdec != 'no'),
  );
  late double _subScale = _s.subtitleScale;
  BoxFit _fit = BoxFit.contain;
  String _hwdec = '';
  double _subDelay = 0, _audioDelay = 0;
  String _secondary = 'no';
  String _error = '';
  Timer? _saver;

  /// mpv itself; null on web, where only basic playback is available.
  // Typed dynamic: the web build of media_kit has no setProperty/command, so they must not be referenced statically.
  dynamic get _mpv => kIsWeb ? null : _player.platform;
  late Playable _item = widget.item;
  late int _index = widget.list?.index ?? 0;

  @override
  void initState() {
    super.initState();
    _hwdec = _s.hwdec;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _player.stream.error.listen((e) => mounted ? setState(() => _error = e) : null);
    _player.stream.completed.listen((done) {
      if (done && _s.autoplayNext && widget.list != null && _index + 1 < widget.list!.length) _go(1);
    });
    _open();
    _saver = Timer.periodic(const Duration(seconds: 5), (_) => _save());
  }

  @override
  void dispose() {
    _saver?.cancel();
    _save();
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _open() async {
    final mpv = _mpv;
    if (mpv != null) {
      await mpv.setProperty('cache', 'yes');
      await mpv.setProperty('demuxer-max-bytes', '${_s.bufferMiB}MiB');
      await mpv.setProperty('demuxer-readahead-secs', '${_s.readaheadSecs}');
      if (_s.preferredLanguages.isNotEmpty) {
        await mpv.setProperty('alang', _s.preferredLanguages);
        await mpv.setProperty('slang', _s.preferredLanguages);
      }
    }
    final start = _s.position(_item.id);
    final url = await LocalProxy.instance.wrap(_item.url, _item.via);
    await _player.open(Media(url, httpHeaders: _item.headers, start: start));
    for (final sub in _item.subtitles) {
      final u = await LocalProxy.instance.wrap(sub.url, _item.via);
      if (mpv != null) {
        await mpv.command(['sub-add', u, 'auto', sub.title, sub.language]); // listed, not forced on
      } else {
        await _player.setSubtitleTrack(SubtitleTrack.uri(u, title: sub.title, language: sub.language));
        break; // web: one external subtitle
      }
    }
    if (start != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resumed at ${_fmt(start)}'),
          action: SnackBarAction(label: 'Start over', onPressed: () => _player.seek(Duration.zero)),
        ),
      );
    }
  }

  void _save() {
    final pos = _player.state.position, dur = _player.state.duration;
    if (dur == Duration.zero) return; // nothing loaded yet
    _s.savePosition(_item.id, pos, dur);
    _s.touchRecent(_item.toJson(), pos, dur);
  }

  // Previous or next file of the folder. The current position is saved first, so coming back resumes.
  Future<void> _go(int delta) async {
    final list = widget.list;
    final i = _index + delta;
    if (list == null || i < 0 || i >= list.length) return;
    _save();
    try {
      final next = await list.open(i);
      if (!mounted) return;
      setState(() {
        _item = next;
        _index = i;
        _error = '';
        _secondary = 'no';
      });
      await _open();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _volumeBy(double d) => _player.setVolume((_player.state.volume + d).clamp(0, 100));

  void _seekBy(int secs) {
    final p = _player.state.position + Duration(seconds: secs);
    _player.seek(p < Duration.zero ? Duration.zero : p);
  }

  static String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  Future<void> _openWith() async {
    final url = await LocalProxy.instance.wrap(_item.url, _item.via);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // The proxy link only works while this app is alive; other apps play it like any http stream.
      await AndroidIntent(action: 'action_view', data: url, type: 'video/*').launchChooser('Open with');
    } else {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    }
  }

  // ---- sheets ----

  static String _label(dynamic t) {
    final parts = <String>[
      if ((t.title ?? '').isNotEmpty) t.title,
      if ((t.language ?? '').isNotEmpty) t.language,
      if ((t.codec ?? '').isNotEmpty) t.codec,
      if (t is AudioTrack && (t.channels ?? '').isNotEmpty) t.channels!,
      if (t is VideoTrack && t.w != null) '${t.w}x${t.h}',
    ];
    return parts.isEmpty ? 'Track ${t.id}' : parts.join(' · ');
  }

  Widget _section(String title, List<Widget> chips) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: chips),
      ],
    ),
  );

  // Options open as a centered popup (not an Android-style bottom sheet), on phones and big screens alike.
  Future<void> _popup(String title, WidgetBuilder content) => showDialog(
    context: context,
    builder: (c) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close), tooltip: 'Close'),
                ],
              ),
            ),
            Flexible(child: content(c)),
          ],
        ),
      ),
    ),
  );

  void _tracks() {
    _popup(
      'Audio, subtitles and video',
      (c) => StatefulBuilder(
        builder: (c, set) {
          final tr = _player.state.tracks, cur = _player.state.track;
          final audio = tr.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
          final subs = tr.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
          final video = tr.video.where((t) => t.id != 'auto' && t.id != 'no').toList();
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (audio.isNotEmpty)
                    _section('Audio', [
                      for (final t in audio)
                        ChoiceChip(
                          label: Text(_label(t)),
                          selected: cur.audio.id == t.id,
                          onSelected: (_) => _player.setAudioTrack(t).then((_) => set(() {})),
                        ),
                    ]),
                  _section('Subtitles', [
                    ChoiceChip(
                      label: const Text('Off'),
                      selected: cur.subtitle.id == 'no',
                      onSelected: (_) => _player.setSubtitleTrack(SubtitleTrack.no()).then((_) => set(() {})),
                    ),
                    for (final t in subs)
                      ChoiceChip(
                        label: Text(_label(t)),
                        selected: cur.subtitle.id == t.id,
                        onSelected: (_) => _player.setSubtitleTrack(t).then((_) => set(() {})),
                      ),
                  ]),
                  if (_mpv != null && subs.length > 1)
                    _section('Second subtitle', [
                      for (final id in ['no', ...subs.map((t) => t.id)])
                        ChoiceChip(
                          label: Text(id == 'no' ? 'Off' : _label(subs.firstWhere((t) => t.id == id))),
                          selected: _secondary == id,
                          onSelected: (_) async {
                            await _mpv.setProperty('secondary-sid', id);
                            set(() => _secondary = id);
                          },
                        ),
                    ]),
                  if (video.length > 1)
                    _section('Video', [
                      for (final t in video)
                        ChoiceChip(
                          label: Text(_label(t)),
                          selected: cur.video.id == t.id,
                          onSelected: (_) => _player.setVideoTrack(t).then((_) => set(() {})),
                        ),
                    ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _stepper(String label, String value, VoidCallback minus, VoidCallback plus) => Row(
    children: [
      Expanded(child: Text(label)),
      IconButton(onPressed: minus, icon: const Icon(Icons.remove), tooltip: '$label down'),
      SizedBox(width: 64, child: Text(value, textAlign: TextAlign.center)),
      IconButton(onPressed: plus, icon: const Icon(Icons.add), tooltip: '$label up'),
    ],
  );

  void _quick() {
    _popup(
      'Playback',
      (c) => StatefulBuilder(
        builder: (c, set) {
          final mpv = _mpv;
          void update(VoidCallback f) {
            setState(f);
            set(() {});
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('Speed', [
                    for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                      ChoiceChip(
                        label: Text('${r}x'),
                        selected: _player.state.rate == r,
                        onSelected: (_) => _player.setRate(r).then((_) => set(() {})),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  if (mpv != null) ...[
                    _stepper(
                      'Subtitle delay',
                      '${_subDelay.toStringAsFixed(1)} s',
                      () {
                        update(() => _subDelay -= 0.1);
                        mpv.setProperty('sub-delay', '$_subDelay');
                      },
                      () {
                        update(() => _subDelay += 0.1);
                        mpv.setProperty('sub-delay', '$_subDelay');
                      },
                    ),
                    _stepper(
                      'Audio delay',
                      '${_audioDelay.toStringAsFixed(1)} s',
                      () {
                        update(() => _audioDelay -= 0.1);
                        mpv.setProperty('audio-delay', '$_audioDelay');
                      },
                      () {
                        update(() => _audioDelay += 0.1);
                        mpv.setProperty('audio-delay', '$_audioDelay');
                      },
                    ),
                  ],
                  _stepper(
                    'Subtitle size',
                    '${(_subScale * 100).round()}%',
                    () => update(() => _subScale = (_subScale - 0.1).clamp(0.5, 3.0)),
                    () => update(() => _subScale = (_subScale + 0.1).clamp(0.5, 3.0)),
                  ),
                  _section('Picture', [
                    for (final (f, l) in [(BoxFit.contain, 'Fit'), (BoxFit.cover, 'Fill'), (BoxFit.fill, 'Stretch')])
                      ChoiceChip(label: Text(l), selected: _fit == f, onSelected: (_) => update(() => _fit = f)),
                  ]),
                  if (mpv != null)
                    _section('Decoder', [
                      for (final (v, l) in [
                        ('auto-safe', 'Hardware'),
                        ('auto-copy', 'Hardware (copy)'),
                        ('no', 'Software'),
                      ])
                        ChoiceChip(
                          label: Text(l),
                          selected: _hwdec == v,
                          onSelected: (_) async {
                            await mpv.setProperty('hwdec', v);
                            update(() => _hwdec = v);
                          },
                        ),
                    ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = _s.seekStep;
    final list = widget.list;
    final back = {5: Icons.replay_5, 10: Icons.replay_10, 30: Icons.replay_30}[step] ?? Icons.replay;
    final fwd = {5: Icons.forward_5, 10: Icons.forward_10, 30: Icons.forward_30}[step] ?? Icons.forward;
    final theme = MaterialVideoControlsThemeData(
      seekOnDoubleTap: true,
      seekOnDoubleTapBackwardDuration: Duration(seconds: step),
      seekOnDoubleTapForwardDuration: Duration(seconds: step),
      volumeGesture: true,
      brightnessGesture: true,
      speedUpOnLongPress: true,
      topButtonBar: [
        MaterialCustomButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            list == null ? _item.title : '${_item.title}  ·  ${_index + 1} / ${list.length}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        MaterialCustomButton(icon: const Icon(Icons.closed_caption_outlined), onPressed: _tracks),
        MaterialCustomButton(icon: const Icon(Icons.tune), onPressed: _quick),
        MaterialCustomButton(icon: const Icon(Icons.open_in_new), onPressed: _openWith),
      ],
      primaryButtonBar: [
        const Spacer(flex: 2),
        if (list != null)
          MaterialCustomButton(
            icon: Icon(Icons.skip_previous, color: _index > 0 ? null : Colors.white24),
            iconSize: 32,
            onPressed: () => _go(-1),
          ),
        const Spacer(),
        MaterialCustomButton(icon: Icon(back), iconSize: 36, onPressed: () => _seekBy(-step)),
        const Spacer(),
        const MaterialPlayOrPauseButton(iconSize: 56),
        const Spacer(),
        MaterialCustomButton(icon: Icon(fwd), iconSize: 36, onPressed: () => _seekBy(step)),
        const Spacer(),
        if (list != null)
          MaterialCustomButton(
            icon: Icon(Icons.skip_next, color: _index + 1 < list.length ? null : Colors.white24),
            iconSize: 32,
            onPressed: () => _go(1),
          ),
        const Spacer(flex: 2),
      ],
      bottomButtonBar: [
        const MaterialPositionIndicator(),
        const Spacer(),
        MaterialCustomButton(
          icon: const Icon(Icons.aspect_ratio),
          onPressed: () =>
              setState(() => _fit = {BoxFit.contain: BoxFit.cover, BoxFit.cover: BoxFit.fill}[_fit] ?? BoxFit.contain),
        ),
        const MaterialFullscreenButton(),
      ],
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: _shortcuts(step),
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              MaterialVideoControlsTheme(
                normal: theme,
                fullscreen: theme,
                child: Video(
                  controller: _video,
                  fit: _fit,
                  controls: MaterialVideoControls,
                  subtitleViewConfiguration: SubtitleViewConfiguration(textScaler: TextScaler.linear(_subScale)),
                ),
              ),
              if (_error.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 96,
                  child: Material(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        "Can't play this: $_error. Try \"Open with\" or the software decoder.",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Common player keys (YouTube, VLC, mpv): space/k play-pause, arrows/j/l seek, up/down volume, m mute,
  // n/p next/previous file, [ ] speed, c tracks, s settings, Escape back.
  Map<ShortcutActivator, VoidCallback> _shortcuts(int step) {
    double muted = 0;
    void speed(double d) => _player.setRate((_player.state.rate + d).clamp(0.25, 4.0));
    return {
      const SingleActivator(LogicalKeyboardKey.space): _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.keyK): _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekBy(-step),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekBy(step),
      const SingleActivator(LogicalKeyboardKey.keyJ): () => _seekBy(-step),
      const SingleActivator(LogicalKeyboardKey.keyL): () => _seekBy(step),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _volumeBy(5),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _volumeBy(-5),
      const SingleActivator(LogicalKeyboardKey.keyM): () {
        final v = _player.state.volume;
        _player.setVolume(v > 0 ? 0 : (muted > 0 ? muted : 100));
        muted = v;
      },
      const SingleActivator(LogicalKeyboardKey.keyN): () => _go(1),
      const SingleActivator(LogicalKeyboardKey.keyP): () => _go(-1),
      const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () => _go(1),
      const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () => _go(-1),
      const SingleActivator(LogicalKeyboardKey.bracketLeft): () => speed(-0.25),
      const SingleActivator(LogicalKeyboardKey.bracketRight): () => speed(0.25),
      const SingleActivator(LogicalKeyboardKey.keyC): _tracks,
      const SingleActivator(LogicalKeyboardKey.keyS): _quick,
      const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context),
    };
  }
}
