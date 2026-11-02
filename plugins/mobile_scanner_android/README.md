# Android scanner override

Android implementation from mobile_scanner 7.4.2 (Apache-2.0), retaining its
CameraX and Flutter channel lifecycle. The decoder uses ZXing locally instead of
ML Kit. Google Tasks supplies only the local completion API; no ML Kit, Firebase
or DataTransport component is included. Apple platforms retain the upstream
AVFoundation implementation. android/settings.gradle.kts selects this directory;
the Dart package version is pinned to keep the channel contract aligned.

FlClash uses QR raw text, camera controls and gallery decoding. Automatic ML Kit
zoom suggestions and structured contact/calendar payload parsing are not part of
this implementation.
