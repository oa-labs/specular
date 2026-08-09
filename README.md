# Specular for Android

GMS-free, local-first Markdown notes synced via GitHub — companion to [team-reflect/reflect-open](https://github.com/team-reflect/reflect-open).

See [`docs/reflect-contract.md`](docs/reflect-contract.md) for the GitHub repo file layout and [`docs/plans/2026-08-06-android-github-sync.md`](docs/plans/2026-08-06-android-github-sync.md) for the full implementation plan.

## Project

- `flutter_app/` is the Android application project.
- Package: `com.specular.android`
- minSdk 26, Flutter + Material 3, no Play Services.

**Note:** Specular is an Android application that works with a Reflect backend (via GitHub sync).

## Build

The current app is built from the Flutter project. From the repository root:

```bash
make build-debug      # build/app/outputs/flutter-apk/app-debug.apk
make install-debug    # build and install on a connected Android device
make clean            # remove Flutter build artifacts
```

`make build` and `make install` are aliases for their debug counterparts.
Install requires an Android device or emulator recognized by `flutter devices`.

For Flutter checks, run `flutter analyze` and `flutter test` from `flutter_app/`.

## First run

1. Create a GitHub fine-grained PAT with **Contents: Read & Write** on your Reflect repo (e.g. `joelwreed/reflect-notes`).
2. Build and install the APK (sideload — no Play Services):
   ```bash
   make install-debug
   ```
3. Open **Settings** → paste token + `owner`/`repo` (e.g. `joelwreed` / `reflect-notes`) → Save.
4. Save the GitHub settings — an initial sync is queued in the background, followed by automatic syncs at least every 15 minutes while connected. Edits set `isDirty` and push on the next sync. Conflicts create `Name (conflict YYYY-MM-DD).md`.

## Structure

```
flutter_app/
  lib/          Flutter UI, local note index, GitHub sync, AI, and voice flows
  android/      Android migration boundary and native to-do widget
  test/         Flutter unit tests
```

## GMS-free / Updates

- No `play-services`, `firebase`, or `gms` deps. No telemetry.
- Release is signed locally (`release.keystore` not in git). Distribute via **GitHub Releases**; the app includes no auto-updater yet — either poll `api.github.com/repos/<owner>/<repo>/releases/latest` manually or re-download the APK. A `play` flavor is stubbed for future Play closed track.
