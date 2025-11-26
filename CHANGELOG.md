# Changelog

## [1.1.0] - YYYY-MM-DD
### Added
- XLSX import support and improved CSV import/export.
- Centralized File I/O service (import/export CSV & XLSX).
- In-app update checker and drawer reminder for new versions.
- Camera focus detector service and more reliable auto-capture behavior.
- UI option to explicitly choose CSV or XLSX when loading masterlists.
- Script to rename split-ABI APKs to include app name while preserving ABI token.

### Changed
- Masterlist sorting improved: alphabetical by last name.
- Capture blocked until Subject, Start and Dismiss times are set.
- Extracted camera, file I/O and XLSX parsing into small services for easier debugging.

### Fixed
- Fixed app bar title overflow.
- Fixed Gradle Kotlin DSL Groovy-syntax issues.
- Prevented auto-capture conflicts with image stream/takePicture on some devices.

### Notes
- Update `app-version.json` URLs if you rename APKs in releases.
- CI: the workflow builds APKs on release publish and uploads renamed APK files as release assets.
- Ensure `scripts/rename_apks.sh` APP_BASENAME matches desired file names.