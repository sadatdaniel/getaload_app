# download_me_not app

Flutter app (Android first; the web build is used for testing and may become the server's web panel) for the
self-hosted [download_me_not](https://github.com/sadatdaniel/download_me_not) server. Private for now.

## What it does

- **Servers:** pair by scanning the QR from the server's web panel (Settings, "Pair a phone") or `sudo dmn pair`,
  paste the pairing link, or type address + token (self-signed certificates are pinned by fingerprint). Several
  servers; switch from the header.
- **Downloads:** add links (several at once), magnets, video pages, or `.torrent` files (drop or browse, many at
  once, with an options dialog and "Don't ask again"). Live progress; right click / long press for pause, play
  while downloading, download order (stream vs standard), verify, remove. Clipboard links are offered on launch.
- **Media:** every video and song on the server, Continue watching, search.
- **Files:** grid (GNOME style folders) or list, cached listings, archives open like folders, badges for unfinished
  and cloud-copied files, context menus (open, play, download to phone, rename, move, copy, copy to Drive, delete),
  built-in viewer for text, PDF and images.
- **Player (media_kit/mpv):** tracks, two subtitles with their own position/timing/style, speed, delays, fit,
  decoder, open with, previous/next in the folder, autoplay next, keyboard shortcuts, stats for nerds (i), resume.
  Pinned servers stream through a loopback proxy.
- **Settings (GNOME style):** appearance, player, adding torrents, server (version, certificate), network (torrent
  port check), storage (leftover partial files), Google Drive.

## Layout

`lib/`: `main.dart` (app, theme, navigation), `api.dart` + `transport*.dart` (client; pinned on Android, fetch on
web), `jobs.dart` + `add.dart` (downloads), `files.dart` + `icons.dart` + `viewer.dart` (file manager),
`library.dart` (media), `player.dart` + `proxy*.dart` + `media.dart` (playback), `settings*.dart` +
`server_screen.dart` (settings), `ui.dart` (context menus, settings rows, dialogs), `pair.dart` (adding servers).

## Develop (on the Windows host, not Docker)

```
flutter analyze
flutter test
DMN_TEST_PAIR='dmn://pair?...' flutter test   # also runs the live check against a test server
flutter build web --release --wasm            # preview: .claude/launch.json "app-web" in the server repo
flutter build apk --release
```

Rules from the server repo apply: never commit tokens, pairing links, keystores or personal data; test only
against our own local servers and content (rule 7).
