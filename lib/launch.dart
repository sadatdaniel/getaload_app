// Opens the player. The player (media_kit, mpv bindings) is a deferred library, so the web build only
// downloads it the first time something is played; the first page loads faster.
import 'package:flutter/widgets.dart';

import 'media.dart';
import 'player.dart' deferred as player;

Future<void> play(BuildContext context, Playable item, {Playlist? list}) async {
  await player.loadLibrary();
  if (context.mounted) await player.play(context, item, list: list);
}
