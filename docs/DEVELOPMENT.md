# Developing the getaload app

## Layout

`lib/`: `main.dart` (app, theme, navigation), `api.dart` + `transport*.dart` (client; pinned on Android, fetch on
web), `jobs.dart` + `add.dart` (downloads), `files.dart` + `icons.dart` + `viewer.dart` (file manager),
`library.dart` (media), `watch.dart` (watch progress on the server), `users.dart` (your devices, server control, people),
`player.dart` + `proxy*.dart` + `media.dart` (playback), `settings_screen.dart` (the topic list; a GNOME-style sidebar on
wide screens, one page per topic on phones), `settings.dart` (this device's choices, positions, Continue watching),
`server_screen.dart` (server, network, add-ons, downloads and Drive sections, picked with `only:`), `ui.dart` (context
menus, settings rows, dialogs), `pair.dart` (adding servers and signing in with name + PIN).

## How a few things work

- **Server control:** a person's sign-in token reaches only their own data. Server-wide changes use the device's
  admin key (`Server.adminKey`, from a `sudo getaload admin` code in Settings, Server control): build those calls with
  `Api(server.asAdmin)`. A refused admin key never raises the "sign in again" banner.
- **Watch progress:** one position per file per person, stored on the server as the preference `w_<hash>` (see
  `watch.dart`). Every place that plays a server file uses the identity `server:<url>::<path>` with `source` set, so
  Downloads, Files and Media share one position and one Continue watching entry. The player asks the server first and
  saves nothing before the resume point is reached.
- **Web client:** the same app, built into the server (below).

## Develop (on the Windows host, not Docker)

```
flutter analyze
flutter test
GETALOAD_TEST_URL=https://127.0.0.1:8080 GETALOAD_TEST_TOKEN=... flutter test   # also runs the live check against a test server
flutter build web --release --wasm --no-web-resources-cdn -o build/web_srv   # then in the server repo:
                                              # sh scripts/webapp.sh ../download_me_not_app/build/web_srv, preview "webui-users"
flutter build apk --release
```

Rules from the server repo apply: never commit tokens, keystores or personal data; test only
against our own local servers and content (rule 7).

## Releases

Tag `vX.Y.Z` and push the tag: `.github/workflows/release.yml` builds the APKs signed with the release key (repo
secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`; alias `getaload`), checks the signature and publishes
them with `checksums.txt`. Installed apps find the release under Settings, About this app. Local builds are signed
with the debug key and cannot update a release install. After an app release, the server repo bundles it as the web
client: set `internal/webui/APP_VERSION` to the tag, then release the server.
