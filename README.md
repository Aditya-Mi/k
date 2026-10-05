# k

A personal payment logger for Android. k reads bank SMS and bank alert emails on the phone, logs each payment, matches the SMS and email of the same payment, and spots subscriptions. Everything stays on the device in an encrypted database; backups are encrypted before they reach your own Google Drive.

Built with Flutter (Kotlin only for SMS capture). Sideloaded, not on the Play Store.

## Install and update

Download the latest `k-x.y.z.apk` from [Releases](../../releases) and open it on the phone. After that, k checks for a newer release when it opens (and from Settings → About → Check for updates), downloads it, verifies its SHA-256 and hands it to Android's installer. Your data stays.

## Develop

```
flutter pub get
flutter test                              # app tests
(cd packages/txn_parser && dart test)     # parser tests
flutter analyze
flutter run
```

`packages/txn_parser` is the pure-Dart parser: banks, sender rules and message formats. See `CLAUDE.md` for layout and conventions, `DESIGN.md` for the design system.

## Release

Actions → **Release** → Run workflow (from `main`): choose the bump (patch, minor, major; `none` only for the version already in `pubspec.yaml`) and write the notes shown in the app's update dialog. The workflow tests, builds a signed APK, checks the signing key, commits the version, tags `vx.y.z`, publishes the GitHub release and updates the update gist.

Versions are semver `x.y.z` (parts 0–99); the Android versionCode is `x·10000 + y·100 + z`, so 1.2.3 is 10203.
