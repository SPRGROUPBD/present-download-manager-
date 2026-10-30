# Present Download Manager v1.2.0

Flutter source starter for Windows and Android.

## Package
Download the source ZIP from the repository file `Present_Download_Manager_v1.2.0_Source.zip`.

## Included
- HTTP/HTTPS URL download
- Progress display and cancel action
- App-private Downloads folder
- System light/dark theme

## Not yet implemented
Torrent/Magnet engine, reliable pause/resume, background service/notifications, scheduler, speed limiter, browser integration, and signed release binaries are roadmap items and are not yet working in this starter.

## Build
Run `flutter create --platforms=android,windows .`, then `flutter pub get`.
Windows: `flutter build windows --release`
Android: `flutter build apk --release`

Repository: https://github.com/SPRGROUPBD/present-download-manager-
