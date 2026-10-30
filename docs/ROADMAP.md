# v1.2.0 implementation roadmap

The ZIP contains the initial HTTP/HTTPS download foundation. Planned work:

1. Resume support using HTTP Range and server capability checks.
2. Queue manager with concurrent-download limit.
3. Persistent download database.
4. Background download service and Android notification channel.
5. Per-download and global speed limits.
6. Scheduler with start/end windows.
7. aria2/libtorrent integration for torrent and magnet links.
8. Browser handoff and URL interception.
9. Windows installer and Android release signing.

Each feature needs platform-specific implementation and device testing before release.
