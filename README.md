# getaload app

Flutter app (Android first; the web build is used for testing and may become the server's web panel) for the
self-hosted [getaload](https://github.com/sadatdaniel/getaload) server. Private for now.

## What it does

- **Servers and sign-in:** type the server address (or scan/paste the pairing QR/link for the address and certificate),
  then pick your name and enter your 4-digit PIN; the device gets its own token and stays signed in. Self-signed
  certificates are pinned by fingerprint (trust on first use). A server without users takes a token instead. Several
  servers; switch from the header.
- **Users:** Settings, "Your account" (change PIN, signed-in devices, sign out); the owner also gets "Users" (add,
  reset PIN, remove). Add-on and Google Drive management are owner-only. Watch progress follows the user across
  devices (server preferences `w_*`).
- **Site sign-ins** (Settings): sign in to a site inside the app (Android; the session goes to the server as your
  cookies, then the phone forgets it) or import a cookies.txt. Each user has their own; only their downloads use them.
- **Add-ons that block the server** (many refuse cloud servers): adding one offers "Ask from this phone", or tap
  the server/phone icon on an add-on. The phone then fetches only its JSON (titles, sources); a chosen source
  always goes to the server, which does all downloading and torrenting (`phone_addons.dart`).
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
`library.dart` (media), `watch.dart` (watch progress on the server), `users.dart` (account and users), `player.dart` + `proxy*.dart` + `media.dart` (playback), `settings*.dart` +
`server_screen.dart` (settings), `ui.dart` (context menus, settings rows, dialogs), `pair.dart` (adding servers and signing in).

## Develop (on the Windows host, not Docker)

```
flutter analyze
flutter test
GETALOAD_TEST_PAIR='getaload://pair?...' flutter test   # also runs the live check against a test server
flutter build web --release --wasm            # preview: .claude/launch.json "app-web" in the server repo
flutter build apk --release
```

Rules from the server repo apply: never commit tokens, pairing links, keystores or personal data; test only
against our own local servers and content (rule 7).
