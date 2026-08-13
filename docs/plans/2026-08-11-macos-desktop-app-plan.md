# Specular for macOS — Desktop App Plan

**Drafted:** 2026-08-11
**Implementation status updated:** 2026-08-12

**Workspace:** `/Users/jreed/Source/specular`  
**Implementation:** Flutter app in `flutter_app/`, with a new native macOS
runner only for Apple-platform integration.

## Goal

Ship a signed macOS desktop version of Specular that preserves the local-first
Markdown and GitHub synchronization model, keeps credentials in the macOS
Keychain, and is comfortable in a resizable desktop window.

The first release supports notes, dailies, tasks, GitHub sync, attachments,
optional AI, and voice transcription. It must not promise Android-equivalent
background execution after the app has quit. A subsequent desktop phase adds a
user-controlled menu-bar (tray) experience and explicit meeting recording.

## Implementation Status

The work below is the state of the repository as of 2026-08-12. “Implemented”
means code and project files exist; it does not substitute for the manual,
sandboxed-device, signing, or notarization validation listed later in this
plan.

| Area | Status | What is complete / what remains |
|---|---|---|
| macOS runner and metadata | Implemented | `flutter_app/macos/` is generated and configured as `Specular` (`com.specular.app`), macOS 11+, with Specular app icons and 1200×800 default / 720×560 minimum window size. Local debug compilation remains unverified because CocoaPods is not installed on the development machine. |
| Sandbox and privacy | Implemented; manual verification pending | Debug and release entitlements permit sandboxing, outgoing network access, user-selected read-only files, and microphone input. `NSMicrophoneUsageDescription` is present. Fresh-install Keychain, SQLite, private-repository, image-picker, and microphone tests remain open. |
| Capability boundaries | Implemented | A centralized `PlatformCapabilities` abstraction makes widgets, camera import, durable sync, foreground recording, and portable-document support explicit. Android behavior remains enabled. |
| Attachments | Implemented for macOS file import | macOS exposes one “Choose image…” action and hides the unsupported camera action. File-chooser cancellation/import still needs device testing. |
| Widget, backup documents, and Android migration | Intentionally unavailable on macOS | The home-widget bridge is a no-op, Android-private data is not read, and Android document-picker-based portable export/import is hidden. A native macOS backup flow is future work. |
| Voice capture | Implemented; manual verification pending | Cross-platform microphone recording remains enabled. Android foreground-service/free-space calls and background retries are skipped on macOS. Permission grant/deny/re-enable and recording/transcription need sandboxed-device testing. |
| Sync | Implemented with macOS-limited semantics | macOS runs configured sync on startup, resume, local changes, and a best-effort in-process timer only while the app is open. Settings says it does not run after quit. |
| Desktop UI | Partially implemented | Navigation rail, native macOS menu bar, create controls, and Cmd-N/Cmd-T/Cmd-F/Cmd-R/Cmd-S/Escape shortcuts exist at desktop widths. The planned persistent note-list plus detail/editor pane has not been implemented; pages still use the existing routed layout. |
| Automated verification | Partially implemented | Capability coverage and a macOS CI workflow (`analyze`, `test`, debug build) were added. Widget tests for desktop image actions/wording and resize/shortcut smoke tests, plus CI execution results, remain open. |
| Packaging and release | Not started | Developer ID signing, notarization, stapling, DMG creation, clean-Mac install/upgrade testing, and GitHub Release publishing await certificate and notarization-credential ownership. |

## Current Findings

| Area | Status | Notes |
|---|---|---|
| macOS Flutter toolchain | Ready | Flutter 3.44.9 detects a local Apple Silicon macOS target. |
| macOS runner | Implemented | `flutter_app/macos/` is committed by this implementation, with a separate `com.specular.app` identifier. |
| Compile compatibility | Pending local verification | The Xcode project resolves its macOS package graph, but `flutter build macos --debug` stops before compilation because CocoaPods is not installed locally and two plugins still need CocoaPods. CI will run the full build on macOS. |
| Database, files, and credentials | Compatible | Drift, `path_provider`, and `flutter_secure_storage` have macOS implementations. A Mac install has its own private app-support folder and Keychain entries. |
| Network and external links | Compatible after entitlement | The sandbox needs outgoing-network access. |
| Gallery attachment import | Compatible after entitlement | `image_picker_macos` uses the file chooser; image quality is ignored. |
| Camera attachment import | Needs a change | The endorsed picker throws for `ImageSource.camera` unless a custom camera delegate is supplied. |
| Voice capture | Compatible after privacy configuration | `record_macos` is present and requests macOS microphone access. |
| Scheduled sync | Implemented with desktop semantics | The app owns a best-effort in-process timer, plus startup and resume synchronization. It never represents that work as durable after quit. |
| Android to-do widget | Intentionally unavailable | There is no macOS equivalent in this scope; `WidgetBridge` is an explicit no-op on desktop. |
| Meeting detection and recording | Planned | Requires a new menu-bar integration, explicit recording consent, microphone permission, Screen Recording permission for system audio, and a privacy/security review. |

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
5. **Meeting recording:** make it an opt-in desktop feature rather than an
   automatic recorder. The menu bar must always show whether recording is
   active, require the user to start each recording, clearly name microphone
   and system-audio sources, and keep audio local until the user requests
   transcription or sync. Every completed meeting recording is transcribed and
   saved as a local Markdown meeting note; its audio remains available locally
   for review/retry and is never automatically uploaded. Users are responsible
   for obtaining consent from all participants and complying with applicable
   recording laws and policies.
6. **Meeting detection:** detect Zoom and Microsoft Teams from running-app
   identity and, where permission allows, windows. For browser meetings, use a
   separately installed browser extension for supported Chromium browsers;
   do not scrape browser UI through Accessibility by default. Safari support
   is separate work. Detection is advisory and must never start recording.

## Implementation Phases

### 1. Add the macOS target and baseline metadata

**Status: Implemented; local debug build blocked by missing CocoaPods.**

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

**Status: Implemented in project files; fresh sandboxed-install verification
remains open.**

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

**Status: Implemented, except planned widget-test expansion.**

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

**Status: Partially implemented.** Default/minimum sizing, navigation rail,
native menu bar, shortcuts, and desktop create controls are implemented. The
persistent note-list/detail split pane, desktop dialog/bottom-sheet review,
and hands-on mouse/focus/resize validation remain open.

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

**Status: Partially implemented.** The CI workflow and capability tests were
added; `flutter analyze` and the existing test suite pass locally. The macOS
debug build, CI result, targeted desktop widget tests, and manual hardware/
sandbox matrix remain open.

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

**Status: Not started.** A release guide exists, but signing, notarization,
DMG construction, and release publication need credentials and release-owner
approval.

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

### 7. Add a menu-bar meeting recorder

**Status: Planned; not implemented.** This is intentionally after the core
desktop release is buildable and manually validated. It expands the original
non-goals and needs its own privacy/security review before release.

- Add a native `NSStatusItem` integration in the macOS runner (or a maintained
  macOS menu-bar plugin if it meets the same lifecycle and signing needs).
  “Minimize to menu bar” must hide the Flutter window without quitting its
  process; offer a visible **Show Specular** action and an explicit **Quit
  Specular** action. Make “close window to menu bar” an opt-in preference so
  the standard macOS close behavior is not silently changed.
- Give the menu bar a clear idle/detecting/recording/error state, including an
  unmistakable recording indicator and elapsed time. It must offer **Start
  recording**, **Stop recording**, **Show current recording**, and **Show
  Specular**. Never begin recording merely because a meeting is detected.
- Build a `MeetingDetector` abstraction that reports an advisory meeting
  candidate: provider, title if available, process/window identity, and
  confidence. Detect Zoom and Teams through known bundle identifiers plus
  running-app/window information. Treat renamed apps, unknown variants, and
  unavailable window titles as no/low-confidence detection rather than a
  false assertion.
- Implement browser detection as an opt-in companion extension for supported
  Chromium browsers (initially Chrome and Edge). The extension should inspect
  only tabs for explicitly supported meeting domains, send the smallest
  possible meeting-state payload to the local app, and expose its permissions
  and privacy policy. Do not require Accessibility permission or inspect
  arbitrary page content. Scope Safari and Firefox separately.
- Record microphone and system audio as separate, timestamped local tracks;
  preserve source metadata and optionally create a mixed listening copy after
  recording. Use `ScreenCaptureKit` for system audio and an audio-input API
  for the microphone. System-audio capture requires the user to grant macOS
  Screen Recording permission; microphone capture requires the existing
  microphone permission. Add precise `Info.plist` purpose strings and only
  the entitlements Apple documents as required for the selected APIs.
- Design for failure: reject or visibly degrade when either permission is
  denied, the selected audio device disappears, storage is low, the app quits,
  or ScreenCaptureKit cannot provide system audio. Do not claim that “system
  audio” isolates only the meeting—make clear that it can include other Mac
  audio. Default to separate tracks and avoid feedback by recommending a
  headset when speakers are active.
- Store recordings in the app-support directory with atomic manifests, then
  provide a review screen for playback, deletion, export, and transcription.
  On stop (or recovery of an interrupted recording), transcribe the saved
  tracks and create a local meeting note using a stable Markdown template:
  title, detected/advisory provider, started/ended timestamps, source status,
  recording ID, and transcript. Link the note to local recording metadata, not
  an absolute audio path or a GitHub-uploadable attachment. Keep the note in a
  configurable `meetings/` folder and mark it as pending transcription while
  retrying. Do not automatically upload audio to GitHub, AI providers, or
  another service. If transcription uses a configured remote provider, request
  an explicit per-recording confirmation that identifies the provider and
  tracks being sent; local/offline transcription may be added later. Keep
  existing voice-note transcription separate from meeting transcription until
  retention and consent behavior is specified.
- Add pause/resume, app termination, sleep/wake, input-device change, and
  interrupted-write recovery behavior. A stopped/interrupted recording must
  remain discoverable and never be silently discarded.
- Test on Apple Silicon and Intel Macs for Zoom, both current Teams variants,
  supported browser meeting tabs, no-meeting state, permissions denied and
  re-enabled, headphones and speakers, sleep/wake, and window hide/restore.
  Include unit tests for detection normalization and integration tests for
  recording state transitions using mocked capture sources.

**Deliverable:** a user-controlled menu-bar app that can be minimized without
quitting, shows advisory meeting detection, and locally records clearly
consented microphone and system-audio tracks with reliable recovery. Each
completed or recovered recording has a durable, transcribed Markdown meeting
note ready to review and sync as text.

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
| `flutter_app/macos/Runner/AppDelegate.swift` and new native menu-bar files | Status-item lifecycle, window hide/restore, and native ScreenCaptureKit bridge. |
| `flutter_app/lib/src/meeting/` | Meeting detection, recording state machine, manifests, retention, and local playback/export domain logic. |
| `flutter_app/lib/src/platform/meeting_bridge.dart` | Typed Flutter/native bridge for menu-bar state, permissions, detection events, and audio capture. |
| `browser_extension/` (new) | Opt-in Chromium meeting-domain detector and local-app handoff; Safari/Firefox remain separately scoped. |
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
- When phase 7 is released, menu-bar recording is opt-in, visibly active while
  running, never automatic from detection, and resilient to interruption.
- A completed meeting recording creates or resumes a durable meeting note;
  only its Markdown transcript is eligible for normal GitHub note sync, never
  raw meeting audio by default.

## Non-goals for the First macOS Release

- Android local-data migration or automatic transfer of Android credentials.
- Launch-at-login or guaranteed sync after quit.
- A macOS widget, iCloud/CloudKit sync, or a native Swift rewrite.
- Native camera capture; file-based image import is the initial desktop path.
- Mac App Store distribution until direct distribution is stable.
- Automatic recording, covert recording, browser UI scraping through
  Accessibility, or automatic upload of meeting audio.
