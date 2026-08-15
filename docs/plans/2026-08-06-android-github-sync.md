# Specular for Android — GitHub Sync Plan

**Originally drafted:** 2026-08-06

**Refreshed:** 2026-08-11

**Workspace:** `/Users/jreed/Source/specular`
**Implementation:** Flutter app in `flutter_app/`, with native Kotlin only for Android platform integrations.

## Goal

Ship a GMS-free, local-first Android app that can view, create, edit, search, and synchronize a Reflect-compatible Markdown repository through GitHub. Notes remain usable offline, and synchronization must not silently discard local work.

GitHub is the only remote in v1; Specular does not depend on a Reflect server, Firebase, or other Play Services.

## Current Status

The local-first MVP and bidirectional GitHub sync are implemented. The source of truth for the on-disk repository format is [the Reflect sync contract](../reflect-contract.md).

| Area | Status | Notes |
|---|---|---|
| Reflect contract validation | Complete | Grounded against a real `reflect-notes` repository. |
| Local notes, dailies, search, CRUD | Complete | Flutter UI backed by Drift/SQLite and local Markdown files. |
| Markdown, links, images | Complete | AppFlowy editor, preview rendering, relative links, camera/gallery attachments. |
| GitHub repo picker and PAT authentication | Complete | Fine-grained PAT is stored with `flutter_secure_storage`. |
| Initial and incremental pull | Complete | Git tree/blob API with SHA comparison. |
| Push, rename, deletion, attachments | Complete | Batched Git Data API commit and atomic ref update. |
| Conflict preservation | Complete | Local content is retained as a dated conflict note. |
| Background and foreground sync | Complete | Manual/on-resume sync plus Android WorkManager periodic work. |
| Sync settings and recovery UX | Complete | Configurable 15-minute to daily cadence, explicit cache clear/repository switch, wiki-link picker, and rate-limit reset messages. |
| GitHub OAuth App with PKCE | Planned | Tracked in the [product roadmap](../roadmap.md#foundation--harden-sync-and-ship-reliably); PAT remains the supported authentication method. |
| Large-repo performance verification | Planned | Tracked in the [product roadmap](../roadmap.md#foundation--harden-sync-and-ship-reliably); no measured 2k-note cold-start or sync benchmark yet. |
| Release automation | Planned | Tracked in the [product roadmap](../roadmap.md#foundation--harden-sync-and-ship-reliably); no CI workflow, signed release artifact, or device-test pipeline yet. |

## Implemented Architecture

```
GitHub repository (Markdown + attachments)
       ⇅ GitHub Git Data REST API (Dio)
Local Markdown and attachment files
       ⇅ NoteRepository
Drift / SQLite index, tasks, dirty state, sync journal, leases
       ⇅ Riverpod providers
Flutter Material 3 UI
```

### Technology decisions

| Concern | Implemented choice | Rationale |
|---|---|---|
| App and UI | Dart, Flutter, Material 3, `go_router`, Riverpod | One portable UI while retaining Android-native integrations where needed. |
| Local index | Drift / SQLite | Stores notes, tasks, attachment state, dirty state, a durable sync journal, and inter-isolate leases. Search uses a shared Dart ranked full-text matcher, avoiding an optional SQLite FTS dependency. |
| Local files | App-private files directory | Canonical Markdown and attachment bytes are retained locally for offline editing and sync. |
| Markdown | AppFlowy Editor and `flutter_markdown_plus` | Structured mobile editing, Markdown rendering, relative links, and image previews. |
| GitHub sync | GitHub Git Data REST API via Dio | Supports atomic multi-file commits without JGit, the NDK, or a bundled git implementation. |
| Credentials | `flutter_secure_storage` | Keeps PAT and optional AI/voice keys in platform-secure storage. |
| Background work | `workmanager` | Android-compatible periodic and one-off network work. |
| Native Android | Kotlin | Home-screen to-do widget, recording foreground service, and Flutter method channels. |

## Reflect Repository Contract

Supported files follow the documented Reflect contract:

- Markdown notes at the repository root and under `notes/`; daily notes under `daily/YYYY-MM-DD.md`.
- The first H1 is the title. A frontmatter `id` is the canonical note identity; daily notes without one are identified by path.
- `[[wikilinks]]`, relative Markdown links, and standard Markdown image links are preserved.
- Images are read from both `attachments/` and `assets/`; new mobile images go to `attachments/`.
- `*.reflect.md` asset sidecars and `.reflect/` local metadata are not notes.

## Sync Behavior

1. A local edit is written to private storage and marked dirty in Drift before network work is requested.
2. Sync fetches the repository ref and walks its Git trees. Changed Markdown blobs and attachments are downloaded by SHA; unchanged blobs are skipped.
3. If a remote update collides with a dirty local note, Specular writes a dated conflict copy, then accepts the remote version. The conflict copy remains dirty and is uploaded on a later push.
4. Dirty attachments and notes are assembled into a tree, committed together, and published with a non-forced ref update. A rejected concurrent ref update triggers one fresh pull-and-retry cycle.
5. Delete and rename operations are persisted in the local sync journal so intent survives process death. A note is marked clean only after its exact local revision is acknowledged by the remote commit.

See [SYNC.md](../SYNC.md) for setup, operational behavior, and recovery guidance.

## Follow-on Work

The remaining authentication, sync-hardening, performance, verification, and
release work is now owned by the
[product roadmap](../roadmap.md#foundation--harden-sync-and-ship-reliably).
Keeping it there lets the sync plan document the implemented architecture while
the roadmap prioritizes cross-cutting delivery work with future product phases.

## Validation Commands

Run these from `flutter_app/`:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

Before release, also run the integration suite on an API 26+ device/emulator, perform the manual conflict scenario above, and measure the documented large-repository targets.

## Non-goals for v1

- iCloud/CloudKit, GitLab/Gitea, self-hosted Git, or a Reflect backend
- Play Services, Firebase, telemetry, or mandatory Google account use
- Graph view, backlinks, tag filtering, plugins, widgets beyond the existing Android to-do widget, Wear OS, real-time collaboration, and AI agent features
- Git history/blame UI and automatic Markdown hunk merges

## Distribution

The primary target is a signed, sideloadable APK. It has no Play Services dependency and may be published through GitHub Releases. Signing material stays outside the repository; see `flutter_app/android/key.properties.example`.
