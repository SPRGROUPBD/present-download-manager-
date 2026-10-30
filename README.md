# Present Download Manager v1.4.1

Flutter download manager for Android and Windows.

## Features
- HTTP/HTTPS file downloads with live progress.
- Retry failed downloads and cancel active downloads.
- URL paste support and filename detection.
- FDM-inspired download list with All, Active, Completed, YouTube, Video and Music categories.
- General, Progress and Connections detail tabs.
- Start.io Android banner and Unity Android interstitial integration.
- GitHub Actions builds Android APK and Windows x64 release ZIP.

## Not included
Torrent support (Magnet links, .torrent files and libtorrent) has been removed from this release. The previous native libtorrent dependency could not reliably retrieve its required native binaries and caused Android OpenSSL and Windows CMake build failures.

YouTube page downloading is not implemented. Use a direct HTTP/HTTPS media file URL or the platform's own download/save feature.

## Build requirements
- Flutter stable with Dart 3.5 or later.
- Android SDK / JDK 17 for APK.
- Visual Studio 2022 with Desktop development with C++ workload for Windows.

## Build
```bash
flutter create --platforms=android,windows .
flutter pub get
flutter build apk --release
flutter build windows --release
```

## Ads
Ads are Android-only. Start.io banner and Unity interstitial use the supplied app/game IDs. Ad delivery depends on provider approval, inventory, app configuration, region and network. Windows ad integration is not included.

## CI artifacts
GitHub Actions uploads:
- `Present-Download-Manager-Android-APK`
- `Present-Download-Manager-Windows-x64`

Repository: https://github.com/SPRGROUPBD/present-download-manager-
