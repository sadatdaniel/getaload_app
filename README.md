# download_me_not app

Android app (Flutter) for the self-hosted [download_me_not](https://github.com/sadatdaniel/download_me_not)
server. Private for now.

- Pair by scanning the QR from the server's web panel (Settings, "Pair a phone") or `sudo dmn pair`;
  several servers can be saved and switched from the title bar.
- Self-signed servers are pinned by the SHA-256 fingerprint from the pairing code (`lib/api.dart`).
- On launch the app offers to download a link or magnet found on the clipboard.
- The API contract is `api/openapi.json` in the server repo.

## Develop (on the Windows host, not Docker)

```
flutter analyze
flutter test
DMN_TEST_PAIR='dmn://pair?...' flutter test   # also runs the live check against a test server
flutter build apk --release
```

Rules from the server repo apply: never commit tokens, pairing links, keystores or personal data;
test only against our own local servers and content.
