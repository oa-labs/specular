# Specular for Android

GMS-free, local-first Markdown notes synced via GitHub — companion to [team-reflect/reflect-open](https://github.com/team-reflect/reflect-open).

See [`docs/reflect-contract.md`](docs/reflect-contract.md) for the GitHub repo file layout and [`docs/plans/2026-08-06-android-github-sync.md`](docs/plans/2026-08-06-android-github-sync.md) for the full implementation plan.

## Project

- `specular/` is the Android project root (this directory).
- Package: `com.specular.android`
- minSdk 26, target 35, Compose + Material 3 + amber accent (`#D97706`), no Play Services (`gmsFree` flavor).

**Note:** Specular is an Android application that works with a Reflect backend (via GitHub sync).

## Build

```bash
./gradlew assembleGmsFreeDebug      # debug APK
./gradlew assembleGmsFreeRelease    # signed release (needs keystore)
./gradlew testGmsFreeDebugUnitTest  # unit tests (FrontmatterParser etc.)
```

SDK at `/opt/android-sdk` (`local.properties` already set). JDK 17+ required.

## First run

1. Create a GitHub fine-grained PAT with **Contents: Read & Write** on your Reflect repo (e.g. `joelwreed/reflect-notes`), or configure `GitHubAuth.OAUTH_CLIENT_ID` for OAuth.
2. Install APK (sideload — no Play Services):
   ```bash
   adb install app/build/outputs/apk/gmsFree/debug/app-gmsFree-debug.apk
   ```
3. Open **Settings** → paste token + `owner`/`repo` (e.g. `joelwreed` / `reflect-notes`) → Save.
4. Tap sync (refresh) — notes pull from `main` via GitHub REST; edits set `isDirty` and push on next sync. Conflicts create `Name (conflict YYYY-MM-DD).md`.

## Structure

```
app/src/main/java/com/reflect/android/
  ui/           Compose screens (List, Detail, Editor + camera/gallery → assets/, Search, Settings, Onboarding)
  ui/theme/     SpecularTheme (light/dark, accent #D97706 on neutral #1A1A1E)
  domain/model/ Note, NoteListItem
  data/local/   Room (notes + FTS), FileStore (filesDir/notes/), FrontmatterParser
  data/remote/  GitHubApi (Retrofit + Moshi, no GMS), GitHubAuth (EncryptedSharedPreferences)
  data/repo/    NoteRepository
  sync/         SyncEngine (pull/push via Contents + Trees API, conflict copy), SyncWorker
  di/           Hilt AppModule
```

## GMS-free / Updates

- No `play-services`, `firebase`, or `gms` deps. No telemetry.
- Release is signed locally (`release.keystore` not in git). Distribute via **GitHub Releases**; the app includes no auto-updater yet — either poll `api.github.com/repos/<owner>/<repo>/releases/latest` manually or re-download the APK. A `play` flavor is stubbed for future Play closed track.
