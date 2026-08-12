# Specular for macOS — Desktop App Plan

**Drafted:** 2026-08-11

**Workspace:** `/Users/jreed/Source/specular`  
**Implementation:** Flutter app in `flutter_app/`, with a new native macOS
runner only for Apple-platform integration.

## Goal

Ship a signed macOS desktop version of Specular that preserves the local-first
Markdown and GitHub synchronization model, keeps credentials in the macOS
Keychain, and is comfortable in a resizable desktop window.

The first release supports notes, dailies, tasks, GitHub sync, attachments,
optional AI, and voice transcription. It must not promise Android-equivalent
background execution after the app has quit.

## Current Findings

| Area | Status | Notes |
|---|---|---|
| macOS Flutter toolchain | Ready | Flutter 3.44.9 detects a local Apple Silicon macOS target. |
| macOS runner | Not committed | `flutter_app/` has only an Android runner. |
| Compile compatibility | Verified | An isolated copy with a generated runner built with `flutter build macos --debug`. |
| Database, files, and credentials | Compatible | Drift, `path_provider`, and `flutter_secure_storage` have macOS implementations. A Mac install has its own private app-support folder and Keychain entries. |
| Network and external links | Compatible after entitlement | The sandbox needs outgoing-network access. |
| Gallery attachment import | Compatible after entitlement | `image_picker_macos` uses the file chooser; image quality is ignored. |
| Camera attachment import | Needs a change | The endorsed picker throws for `ImageSource.camera` unless a custom camera delegate is supplied. |
| Voice capture | Compatible after privacy configuration | `record_macos` is present and requests macOS microphone access. |
| Scheduled sync | Semantics differ | `workmanager_apple` uses `NSBackgroundActivityScheduler`: opportunistic, while the app is running, not durable work after quit. |
| Android to-do widget | Not applicable | There is no macOS equivalent in this scope; Flutter channel calls already tolerate no native handler. |

## Product Decisions

1. **Distribution:** initially distribute a Developer ID-signed, notarized DMG
   through GitHub Releases. Treat Mac App Store support as separate work.
2. **Sync:** support manual, startup, and resume sync. Describe scheduled sync
   as best-effort; never imply it runs after quit.
3. **Images:** release one uses “Choose image…” through the file chooser. Hide
   Android’s “Take photo” action. Add native camera capture only if required.
4. **Onboarding:** macOS does not read Android-private files or credentials.
   Users populate a new desktop installation through GitHub sync; local
   export/import is deferred.

## Implementation Phases

### 1. Add the macOS target and baseline metadata

- From `flutter_app/`, run `flutter create --platforms=macos .` and commit the
  generated `macos/` runner. Review generated IDE/test files before committing.
- Set a new Apple bundle identifier (for example `com.specular.app`), display
  name `Specular`, and a supported macOS deployment target.
- Replace the generated `AppIcon.appiconset` images with Specular icon assets.
- Add `build-macos-debug` and `build-macos-release` targets to the root
  Makefile, then document local desktop builds in both READMEs.

**Deliverable:** `flutter run -d macos` opens the app and
`flutter build macos --debug` produces `Specular.app`.

### 2. Configure sandbox and privacy access

In both `macos/Runner/DebugProfile.entitlements` and
`macos/Runner/Release.entitlements`:

- retain `com.apple.security.app-sandbox`;
- add `com.apple.security.network.client` for GitHub, AI, transcription, and
  external links;
- add `com.apple.security.files.user-selected.read-only` for attachment import;
- add `com.apple.security.device.audio-input` for voice capture.

In `macos/Runner/Info.plist`, add `NSMicrophoneUsageDescription` explaining
that voice capture records audio for transcription. Add
`NSCameraUsageDescription` only if native camera capture is implemented.

Verify sandboxed debug and release builds can write app-support files and
SQLite, use the Keychain, sync a private GitHub repository, import an image,
and prompt for/record microphone access.

**Deliverable:** all required permissions are minimal, documented, and work in
a fresh sandboxed install.

### 3. Make platform behavior explicit in Dart

- Add a platform-capabilities abstraction in `lib/src/platform/` instead of
  scattering `Platform.isMacOS` checks. It should describe home-widget, camera
  import, durable-background-sync, and foreground-recording support.
- Keep Android migration behavior in `legacy_bridge.dart`; continue using its
  existing app-support-directory branch on macOS. Correct Android-only comments
  that would misdescribe desktop behavior.
- Change `screens.dart` to expose one “Choose image…” action on macOS and the
  existing camera/gallery options on Android.
- Make `WidgetBridge` a deliberate no-op on macOS and remove desktop-only
  Android-widget route assumptions.
- In `voice_service.dart`, call Android foreground-service and free-space method
  channels only on Android. Continue using the cross-platform `record` package
  for macOS microphone recording.
- Split `SyncScheduler` policy by capability. Keep macOS manual/startup/resume
  sync and best-effort in-process scheduling; label its configured interval
  accurately in Settings.
- Add unit tests for capabilities and widget tests for the macOS image actions
  and scheduled-sync wording.

**Deliverable:** every macOS-facing behavior is intentional rather than relying
on missing method-channel exceptions, and Android behavior is unchanged.

### 4. Make the interface desktop-appropriate

- Set sensible default and minimum window sizes in `MainFlutterWindow.swift`.
- Add a desktop breakpoint (around 900 logical pixels): persistent navigation/
  note-list column plus editor/detail pane; retain the phone layout below it.
- Add keyboard shortcuts for new note, new to-do, search, save, sync/refresh,
  and back/close. Surface appropriate actions in a macOS menu bar.
- Verify mouse interaction, scrolling, selection, focus order, dialogs, and
  resize behavior. Replace mobile-only interactions where needed, including a
  floating-action-button-only creation path and full-height bottom sheets.
- Preserve the Material visual system unless a focused macOS adjustment is
  necessary; this is adaptive UX work, not a UI rewrite.

**Deliverable:** core note and sync workflows are usable with a keyboard and
mouse from narrow windows through large displays.

### 5. Verify feature parity and regression safety

Add a macOS CI job that runs:

```bash
cd flutter_app
flutter analyze
flutter test
flutter build macos --debug
```

Add or extend coverage for:

- empty-store startup and initial GitHub sync;
- offline edit/reopen, push, pull, rename, delete, conflict preservation, and
  attachment synchronization;
- Keychain persistence, file-chooser import and cancellation, and microphone
  permission granted/denied/re-enabled paths;
- adaptive resize and keyboard-shortcut smoke tests;
- manual/resume sync and the stated best-effort scheduling behavior.

Manually test a release-sandboxed build on Apple Silicon and Intel Macs with a
private repository, external URL launch, sleep/resume, and quit during sync.

**Deliverable:** a release checklist records macOS results, and the existing
Android test/build suite still passes.

### 6. Package, sign, and release

- Build with a Developer ID Application certificate and release entitlements.
- Sign nested frameworks and the app, submit to Apple notarization, staple the
  result, and create a DMG.
- Test installation on a clean Mac without developer overrides, including
  launch, Keychain access, network sync, and upgrade behavior.
- Publish the notarized DMG and SHA-256 checksum in GitHub Releases with a
  macOS install/update/troubleshooting guide.
- Keep certificates and notarization credentials out of the repository and CI
  logs; add protected CI secrets only after ownership/rotation is decided.

**Deliverable:** a signed, notarized desktop release installable without
bypassing Gatekeeper.

## File-Level Change Map

| Path | Planned change |
|---|---|
| `flutter_app/macos/` | New runner, application metadata, icons, window configuration, entitlements, and privacy strings. |
| `flutter_app/lib/src/platform/` | Capability abstraction and intentional no-op/macOS bridge behavior. |
| `flutter_app/lib/main.dart` | Desktop-safe startup/scheduling initialization. |
| `flutter_app/lib/src/sync/sync_scheduler.dart` | Separate Android durable-work policy from macOS best-effort behavior. |
| `flutter_app/lib/src/voice/voice_service.dart` | Guard Android service/channel logic while retaining cross-platform recording. |
| `flutter_app/lib/src/ui/screens.dart` | Image-source actions, adaptive panes, shortcuts, and accurate sync text. |
| `flutter_app/lib/src/ui/specular_app.dart` | Desktop routing/navigation/menu and responsive layout wiring. |
| `flutter_app/test/` | Capability, macOS UI, scheduling, and adaptive-layout tests. |
| `Makefile` and READMEs | Desktop build commands and setup/release documentation. |
| CI workflow (new) | Analyze, test, and macOS debug-build job. |

## Acceptance Criteria

- A clean checkout builds and launches with `flutter build macos --debug` and
  `flutter run -d macos`.
- Notes, dailies, tasks, attachments, GitHub pull/push/conflicts, AI summaries,
  voice transcription, external links, and Keychain-backed credentials function
  in a sandboxed macOS build.
- Camera capture and Android home-screen widgets are absent or explicitly
  implemented—never exposed as broken actions.
- Scheduled-sync UI accurately says macOS scheduling is best-effort and may not
  run after quit.
- The desktop UI is usable across window sizes with core flows available by
  keyboard.
- Existing Android tests/builds continue to pass.
- Release artifacts are Developer ID signed, notarized, stapled, and installable
  without Gatekeeper bypass.

## Non-goals for the First macOS Release

- Android local-data migration or automatic transfer of Android credentials.
- A menu-bar agent, launch-at-login, or guaranteed sync after quit.
- A macOS widget, iCloud/CloudKit sync, or a native Swift rewrite.
- Native camera capture; file-based image import is the initial desktop path.
- Mac App Store distribution until direct distribution is stable.
