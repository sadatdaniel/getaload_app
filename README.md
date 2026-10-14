<p align="center"><img src="web/icons/Icon-192.png" width="120" alt="getaload"></p>
<h1 align="center">getaload</h1>
<p align="center"><b>Your own download server, in your pocket.</b><br>The Android app for <a href="https://github.com/sadatdaniel/getaload">getaload</a>.</p>

<p align="center">
  <a href="https://github.com/sadatdaniel/getaload_app/releases/latest"><img src="https://img.shields.io/github/v/release/sadatdaniel/getaload_app?label=download" alt="Latest release"></a>
  <a href="https://github.com/sadatdaniel/getaload_app/actions/workflows/release.yml"><img src="https://github.com/sadatdaniel/getaload_app/actions/workflows/release.yml/badge.svg" alt="Build"></a>
</p>

<p align="center">
  <a href="#features">Features</a> · <a href="#install">Install</a> · <a href="#updates">Updates</a> ·
  <a href="#verify-the-apk">Verify the APK</a> · <a href="https://sadatdaniel.github.io/getaload/privacy.html">Privacy</a>
</p>

> **Beta.** getaload is young and changes quickly. It needs a getaload server, which you run yourself:
> [set one up](https://github.com/sadatdaniel/getaload#quick-start) on a VPS, a home server or a Raspberry Pi.

## What it is

Send a link, a video page, a magnet link or a .torrent to your server, and it downloads there, at full speed, while
your phone is in your pocket. Then watch, browse or save the results from the app. Several people can share one
server: everyone signs in with their own name and PIN and sees only their own downloads.

The app talks to your server, which does the downloading. Your sign-ins, cookies and Google Drive connection are
stored encrypted on that server, for you alone.

## Features

- **Downloads**: web files, video pages (YouTube and many more sites) with quality, format and subtitles, magnet
  links and .torrent files. Live progress, pause, resume, play while downloading.
- **Media**: everything playable on your server in one list, with Continue watching that follows you across devices.
- **Player**: two subtitles at once with their own style and timing, audio and subtitle tracks, speed, stats,
  previous and next in the folder, swipe down to close, landscape for landscape videos.
- **Files**: browse your server like a file manager, open archives like folders, view text, PDF and images, rename,
  move, copy, delete, download to the phone.
- **Google Drive**: connect your own Drive and copy finished downloads there.
- **Site sign-ins**: sign in to a site (e.g. YouTube) inside the app, so your downloads from it work signed in.
- **Discover** (optional): browse catalogs from Stremio add-ons you choose; anything you play downloads on your server.
- **Secure by default**: your server's certificate is pinned, every device has its own token, PINs lock after five
  wrong tries.

## Install

1. Download the APK from the [latest release](https://github.com/sadatdaniel/getaload_app/releases/latest).
   Most phones: **`…-arm64-v8a.apk`**. Older 32-bit phones: `…-armeabi-v7a.apk`.
2. Open it and allow installing from your browser or file manager when Android asks.
3. In the app, enter your server's address (`sudo getaload connect` on the server shows it), accept its certificate,
   pick your name and enter your PIN.

## Updates

The app updates itself: **Settings → About this app** shows when a new version is out, and **Update** downloads it,
checks it and hands it to Android. You stay signed in.

## Verify the APK

Releases are signed with the getaload release key. Its SHA-256 certificate fingerprint is:

```
D5:BD:AE:54:7D:FB:4A:3D:5E:D3:42:F8:03:46:14:0D:45:57:2D:49:90:04:F3:39:A9:C3:48:F9:28:72:1A:D0
```

Check a download with `apksigner verify --print-certs getaload-*.apk`. Every release also lists the SHA-256 of each
APK in `checksums.txt`.

## Contributing

Bug reports and ideas are welcome in [issues](https://github.com/sadatdaniel/getaload_app/issues). To build the app
yourself, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Privacy

The app collects nothing. It talks to your own server, to GitHub to check for app updates, and to add-ons you
chose to ask from the phone (they block servers; the phone only looks up titles, the server still downloads). Details:
[privacy policy](https://sadatdaniel.github.io/getaload/privacy.html).

## License

Not chosen yet. Until a licence is added, all rights are reserved.
