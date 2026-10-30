# Present Download Manager v1.2.0

Flutter source starter for Windows and Android.

## Included
- HTTP/HTTPS URL download
- Progress display and cancel action
- App-private Downloads folder
- System light/dark theme
- GitHub Actions workflow to build Android APK and Windows release package

## Build status and limitations
This is an initial source starter, not a finished FDM replacement. Torrent/Magnet engine, reliable pause/resume, background service/notifications, scheduler, speed limiter, browser integration, installer packaging and signed release binaries are not implemented yet.

## Build locally
Generate platform folders and fetch packages:

```bash
flutter create --platforms=android,windows .
flutter pub get
```

Windows:
```bash
flutter build windows --release
```

Android:
```bash
flutter build apk --release
```

## Build using GitHub
The workflow at `.github/workflows/build.yml` runs on pushes to `main` and can also be started manually from **Actions → Build Android APK and Windows App → Run workflow**.

When both jobs succeed, open the workflow run and download:
- `Present-Download-Manager-Android-APK`
- `Present-Download-Manager-Windows-x64` (ZIP containing the EXE and required runtime files)

Repository: https://github.com/SPRGROUPBD/present-download-manager-
