# DITrix Attendance Scanner

DITrix Attendance Scanner is an open-source Flutter app I built to help my section, DIT 1-5, make attendance checking faster and easier. It also serves as my learning experience as a developer.

## What it does
- Scan student IDs with the device camera
- Extract Student ID and surname via on-device OCR (ML Kit) with normalization for common OCR mistakes
- Manage attendance by sessions (subject, time-in, dismiss)
- Load a masterlist (CSV), mark present/late, and export results (CSV/XLSX)
- Dark/Light theme with a subtle green gradient
- Optional Developer Mode to view debug logs and diagnostics

## Key features
- Session-based saving (each Capture ID session is persisted and resumable)
- Robust ID parsing (e.g., 2021-123456-MN-1 with common OCR corrections)
- Exports to CSV/XLSX into a DITrix attendance folder (with fallbacks)
- Onboarding tutorial (skippable)
- Settings for Theme (System/Light/Dark) and Developer Mode

## Build
- Get packages and analyze:
  - `flutter pub get`
  - `dart analyze`
- Android release (AAB/APK):
  - `flutter build appbundle --release`
  - `flutter build apk --release --split-per-abi`
- Linux desktop (optional):
  - `flutter build linux --release`

## Notes
- Camera and storage permissions are required for scanning and exports.
- This project is open source—feel free to explore, learn, and improve it.

Made to help DIT 1-5 and to grow my experience as a developer.