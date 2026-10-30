# Present Download Manager v1.4.0

Flutter download manager for Android and Windows.

## Features
- HTTP/HTTPS file downloads with progress, retry and cancel.
- Add torrent using Magnet URI or a local .torrent file.
- Native libtorrent engine (DHT/PEX/uTP support depends on the libtorrent engine build and network).
- Torrent progress, download/upload rate, peer and seed counts.
- Pause, resume and remove torrent tasks.
- FDM-inspired download list, categories and General/Progress/Connections detail panel.
- Start.io Android banner and Unity Android interstitial integration.
- GitHub Actions builds Android APK and Windows x64 release ZIP.

## Build requirements
- Flutter stable with Dart 3.5 or later.
- Android SDK / JDK 17 for APK.
- Visual Studio 2022 C++ desktop workload for Windows builds.
- Internet access during the first native libtorrent build to fetch its platform binaries.

## Build
```bash
flutter create --platforms=android,windows .
flutter pub get
flutter build apk --release
flutter build windows --release
```

## Torrent engine
The app uses `libtorrent_flutter` 2.0.0, a native libtorrent 2.1.1 wrapper. First build downloads native binaries (the package documents approximately 10–80 MB). The engine stores data in the app Documents/Downloads folder. Torrent downloads need reachable peers/seeds and are not guaranteed to start immediately. Use only content you have the legal right to download and share.

## Ads
Ads are Android-only. Start.io banner and Unity interstitial are production-configured with the supplied app/game IDs. Ad fill depends on provider approval, inventory, app configuration, country and network; a successful build does not guarantee an ad impression. Windows ad integration is not included.

## Licensing notice
`libtorrent_flutter` is licensed under GPL-3.0. Distributing this app with that dependency may require the combined distributed work to comply with GPL-3.0, including providing corresponding source and license notices. Review the dependency license and obtain legal advice before proprietary/commercial distribution.

## CI artifacts
GitHub Actions → latest successful run:
- Android APK artifact: `Present-Download-Manager-Android-APK`
- Windows package artifact: `Present-Download-Manager-Windows-x64`

Repository: https://github.com/SPRGROUPBD/present-download-manager-
