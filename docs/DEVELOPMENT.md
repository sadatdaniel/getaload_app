# Developing the getaload app

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

## Releases

Tag `vX.Y.Z` and push the tag: `.github/workflows/release.yml` builds the APKs signed with the release key (repo
secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`; alias `getaload`), checks the signature and publishes
them with `checksums.txt`. Installed apps find the release under Settings, About this app. Local builds are signed
with the debug key and cannot update a release install.
