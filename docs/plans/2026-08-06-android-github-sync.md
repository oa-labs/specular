# Android App for Reflect — GitHub Sync (Initial Release) — Implementation Plan

**Date:** 2026-08-06  
**Workspace:** `/Users/jreed/Source/specular` (currently empty — greenfield)  
**Upstream vision:** https://github.com/team-reflect/reflect-open/blob/master/docs/reflect-v2-product-vision.md (fetch timed out in sandbox; plan grounded on public README + snippet evidence — see Context)  
**Requested scope:** Android mobile app that works with Reflect; v1 integrates with the GitHub sync backing store.

---

## Goal

Ship an Android app that lets a Reflect user view, create, edit, and search their markdown notes on-device, with bidirectional sync to the same GitHub repository used as the backing store by the Reflect desktop (Mac) client. The app is local-first and offline-capable: edits work offline and converge on next sync without data loss.

## Success Criteria

- User can authenticate via GitHub OAuth (or PAT fallback) and connect an existing Reflect GitHub repo (public or private) already used by the desktop app.
- App displays the correct file tree / note list from that repo, with frontmatter-parsed titles, daily notes, and link-aware rendering.
- User can create, edit (markdown), delete, and rename notes offline; changes persist locally and sync to GitHub when online via commits/pushes that desktop picks up.
- Bidirectional sync: pull remote changes made on desktop before push; no silent overwrites; simple last-write-wins per file with conflict marker fallback for concurrent edits to the same file.
- Search (title + body) works offline.
- Cold start on a 2k-note repo < 2s to interactive note list; incremental sync < 5s on Wi-Fi.
- No Reflect server dependency — GitHub is the only remote.

## Context And Current Facts

- **Workspace state (verified 2026-08-06):** `specular/` is empty (`ls -R` shows only `.`/`..`), not a git repo (`git status` → "not a git repository"). No existing Android project, Gradle, or docs. This is a greenfield app — no reuse constraints.
- **Reflect public facts (from search):
  - `team-reflect/reflect-open` README: "Open-source Reflect rewrite: A local-first AI agent-friendly Markdown note-taking app · in beta and used daily · current focus is the Mac app, iOS … See the V2 product vision and the implementation plans in `docs/plans/` for the longer-term direction." — our vision link timed out on raw + API fetches (`curl`/`urllib` timed out), so verbatim V2 pillars are treated as assumption pending re-fetch.
  - README sync choices: "use iCloud Drive for file sync, or git/GitHub for versioned backup." CLI: `reflect today`, `reflect search`, `reflect show`. Implies each note is a markdown file on disk; GitHub sync is essentially a git repo of markdown files (likely `notes/` + daily notes), not a proprietary API.
  - No published spec for the GitHub sync file layout was retrievable in this session; the exact repo layout, frontmatter schema, and wikilink syntax must be confirmed from a real Reflect GitHub repo.
- **Assumed Reflect file model (to be validated against a real repo):** repo root contains markdown files (e.g., `2025-07-25.md`, `My Note.md`) with YAML frontmatter (`id`, `title`, `created`, `updated`, `tags`), `[[wikilinks]]`, and attachments under `assets/`. Git history is the source of truth; no custom server. This aligns with the local-first + git/GitHub wording.
- **Android baseline (2026):** Kotlin 2.x, Jetpack Compose, Material 3, minSdk 26, targetSdk 35, Gradle 8.x + Kotlin DSL.

## Constraints And Non-goals

**Constraints:**
- v1 uses GitHub as the only backing store; iCloud Drive is *not* supported on Android.
- Must not require a Reflect backend or proprietary API.
- Must handle GitHub rate limits, private repos, and 2FA.
- Offline-first — app is usable airplane-mode.

**Non-goals for initial release:**
- iCloud/CloudKit sync, end-to-end encryption, real-time collaborative editing, AI agent features, graph view, plugins, widgets, or Wear OS.
- Full git history browsing / blame (read history if cheap, but not a history UI).
- Self-hosted git providers (GitLab/Gitea) — design should not preclude them, but not built.

## Key Decisions

| # | Decision | Recommended | Why | Rejected alternative |
|---|----------|-------------|-----|----------------------|
| 1 | **Language / UI** | Kotlin + Jetpack Compose (Material 3) + Compose Navigation | Modern Android standard, fast iteration, strong markdown rendering ecosystem | XML Views / Flutter / React Native — extra bridge, not native feel, harder JGit integration |
| 2 | **Architecture** | Clean: `ui → domain → data`, MVVM + Repository, offline-first | Testable sync logic isolated from UI; mirrors desktop's file-oriented model | MVC / God-Activity — untestable sync |
| 3 | **Local storage** | Room (SQLite) for note index + metadata; files mirrored on device filesystem (`Context.filesDir/notes/`) as canonical markdown | Queryable index for search/list; filesystem preserves git fidelity and allows `git`-based sync later | Only Room *or* only filesystem — loses either query speed or git compatibility |
| 4 | **Markdown rendering/editing** | Render: `markwon` or `mado`-style Compose markdown; Edit: plain-text editor with syntax highlight + toolbar (no WYSIWYG v1) | Lightweight, preserves raw markdown round-trip; WYSIWYG is scope creep | Full WYSIWYG (e.g., ProseMirror) — fidelity risk with Reflect's markdown |
| 5 | **GitHub sync engine — v1** | **GitHub REST/Content API** (`GET /repos/{owner}/{repo}/git/trees`, Contents API, commits via Git Data API *or* single-file `PUT /contents` for simple edits) | No native `libgit2`/`JGit` bundling → smaller APK, no NDK, avoids JGit's large dep and background git complexity; sufficient for file-per-note model; easy OAuth via PAT/fine-grained token | Full JGit clone/pull/push — more faithful to git but heavy (10-15 MB), slower, needs background git work and conflict plumbing; defer to v2 if repo > 10k files or need true merge |
| 6 | **Auth** | GitHub OAuth App (PKCE) → fine-grained PAT fallback; token via EncryptedSharedPreferences | OAuth is expected UX; PAT fallback unblocks dev + enterprise | Only PAT — poor UX; only OAuth — blocks headless/testing |
| 7 | **Sync strategy** | Poll + manual pull-to-refresh; WorkManager periodic sync (15 min) + on-resume sync; ETag/`sha` based change detection; per-file `sha` optimistic concurrency | Deterministic, battery-friendly; WorkManager is OS-compliant | Push via webhook — needs backend; Realtime websocket — not in Reflect model |
| 8 | **Conflict handling** | Last-write-wins per file by `updated` timestamp, with automatic `.conflict` duplicate + banner when both sides edited same `sha` | No data loss, user can resolve; mirrors Obsidian Git plugin behavior | Auto-merge of markdown hunks — too risky for v1 |
| 9 | **Search** | FTS4/FTS5 in Room (offline index built from local files) | Instant offline search, no server | GitHub code search API — online-only, rate-limited |
|10 | **DI / Async** | Hilt + Coroutines + Flow; Room + Retrofit/OkHttp + Moshi/kotlinx.serialization | Standard, testable | Koin/manual DI — less tooling |

## Recommended Approach

### Data flow

```
GitHub Repo (markdown files)
   ⇅  GitHub REST / Git Data API (OkHttp + Retrofit)
   ⇅  sha/ETag + commit
Local Files (filesDir/notes/**.md)  ←→  Room Index (notes, tags, links, FTS)
   ⇅  FileObserver / Repository
Compose UI (NoteList, Editor, Search, Settings)
```

1. **Auth → Repo picker:** OAuth flow → list user's repos → user selects Reflect repo (validate by presence of markdown files / `reflect.json` marker if any).
2. **Initial clone (API):** `GET /git/trees?recursive=1` → download each `.md` via Contents API → write to local files → bulk insert into Room + FTS.
3. **Read path:** Room is source of truth for lists/search; file is source of truth for editor save.
4. **Write path:** Edit → save to local file → update Room (dirty flag) → enqueue `SyncWorker` → `PUT /repos/.../contents/{path}` (with `sha` for concurrency) or batch commit via Git Data API (`create tree → create commit → update ref`) for multi-file saves.
5. **Pull:** Fetch tree sha, compare `sha` map to local `lastRemoteSha`; download changed files; if local dirty + remote changed → create conflict copy.
6. **Push:** Only push dirty files whose `sha` still matches remote; otherwise pull-first.

### Repo layout to support
Probe the real Reflect repo on first connect and adapt: treat any `.md` anywhere as a note; if a `reflect.json`/`config.json` exists, respect its `notesDir`. Record layout version in Room to allow migration.

### Project skeleton
```
app/
 ├─ src/main/java/com/reflect/android/
 │   ├─ ui/ (compose screens: list, editor, search, settings, onboarding)
 │   ├─ domain/ (Note, Link, Tag, SyncState, use cases)
 │   ├─ data/
 │   │   ├─ local/ (Room, FileStore, FtsDao)
 │   │   ├─ remote/ (GitHubApi, GitHubAuth, Dto)
 │   │   └─ repo/ (NoteRepository, SyncRepository)
 │   └─ sync/ (SyncEngine, ConflictResolver, WorkManager workers)
 └─ src/test + androidTest
```

## Work Plan

### Phase 0 — Validation spike (1 week, blocks Phase 1)
- **0.1** Clone `reflect-open`, inspect actual GitHub repo layout, frontmatter, wikilink syntax, and any `docs/plans/` decisions. Re-fetch V2 vision doc when network allows. Record findings in `docs/reflect-contract.md`.
- **0.2** Spike GitHub API vs JGit: prototype tree fetch + single-file commit on a private test repo; measure rate limits (5k/hr) and batch commit feasibility.
- *Dependency:* answers Open Question #1-3 below.

### Phase 1 — Project scaffolding & local-only notes (2 weeks)
- **1.1** Create Android project (Kotlin, Compose, Material 3, Navigation, Hilt, Room, Retrofit). Add `spotless`/`detekt` as in desktop repo if desired.
- **1.2** Data layer: `FileStore` + `Room` entities (`NoteEntity`, `Tag`, `Fts`), FTS, parsers for frontmatter/wikilinks.
- **1.3** UI: `NoteListScreen` (from Room), `NoteDetailScreen` (Markwon render), `EditorScreen` (plain markdown), `SearchScreen` (FTS).
- **1.4** Local CRUD works fully offline; no sync yet.
- *Validation:* unit tests for parser/DAO; screenshot tests for Compose; manual test on 500-file fixture.

### Phase 2 — GitHub auth + read-only sync (2 weeks)
- **2.1** OAuth App registration + PKCE flow + EncryptedSharedPreferences token store + PAT manual entry.
- **2.2** Repo picker + validation.
- **2.3** Initial sync (tree → download) + incremental pull (sha diff) + pull-to-refresh + on-resume sync.
- **2.4** WorkManager periodic sync (15 min when online/charging configurable).
- *Validation:* integration test with mocked GitHubApi (MockWebServer); manual test against real private repo with 1k notes.

### Phase 3 — Bidirectional write + conflicts (2 weeks)
- **3.1** Dirty tracking + enqueue; push via Contents API (single file) then batch Data API for multi-file.
- **3.2** Pull-before-push + ETag/`sha` concurrency + conflict copy + banner + "keep mine / keep theirs / keep both".
- **3.3** Rename/delete handling (delete = `DELETE /contents` or tree without file).
- **3.4** Offline queue persistence (Room `pendingOps`) + retry with exponential backoff.
- *Validation:* concurrency test (edit same file on desktop + mobile); airplane-mode edit → reconnect → no loss.

### Phase 4 — Polish & performance (1.5 weeks)
- **4.1** Editor polish (markdown toolbar, link autocomplete from index, daily note template `today`).
- **4.2** Large-repo perf: pagination, lazy tree fetch, binary attachment skip, FTS incremental updates.
- **4.3** Error UX: rate-limit banner, auth expiry, private repo 404 handling, large file (>1 MB) guard.
- **4.4** Onboarding + settings (sync interval, repo switch, clear local cache).

### Phase 5 — Release readiness (1 week)
- **5.1** Instrumented tests (Espresso/Compose) + snapshot tests + GitHub Actions CI (build, lint, tests).
- **5.2** Closed testing track in Play Console, crash reporting (Firebase Crashlytics, optional), privacy disclosure for GitHub token.
- **5.3** Docs: `README.md`, `SYNC.md` (GitHub contract), import guide from desktop.

**Suggested PR slices (if following plan-as-commits):**
1. `chore: scaffold android project + local note stack`
2. `feat: markdown render + editor + FTS search`
3. `feat: github auth + repo picker`
4. `feat: read-only github sync (tree + pull)`
5. `feat: bidirectional sync + conflict handling`
6. `chore: polish, perf, release config`

## Validation Plan

| Work unit | Command / check | Expected evidence |
|-----------|-----------------|-------------------|
| Parser + DAO | `./gradlew :app:testDebugUnitTest` | All `FrontmatterParserTest`, `WikilinkTest`, `NoteDaoTest` green |
| Compose UI | `./gradlew :app:connectedDebugAndroidTest` or Firebase Test Lab | List/editor/search render; no crashes on rotation |
| GitHubApi mock | MockWebServer integration tests (JUnit) | Tree fetch + commit + 409 conflict paths covered |
| Manual sync | Private `reflect-test` repo: create/edit on Mac → pull on Android → edit offline → airplane push → reconnect | File appears on both sides; conflict copy created when expected |
| Perf | Cold start + incremental sync measured on 2k-note fixture | <2s / <5s as in Success Criteria |
| Lint/gate | `./gradlew spotlessCheck detekt` (if configured); `./gradlew assembleDebug` | No lint errors; debug APK builds |

Highlight highest-risk validation: **bidirectional conflict test** (same file edited on desktop and mobile concurrently) — this is where silent data loss would hide.

## Risks / Rollback

- **Repo layout mismatch:** desktop may use a nested `notes/` dir or custom frontmatter — mitigate with Phase 0 spike and adaptive parser; rollback is local-only mode if API shape diverges.
- **GitHub rate limits (5k/hr per token, Contents API 500 MB):** batch commits where possible; show rate-limit banner and backoff; large repos should switch to shallow tree + incremental sha diff (already planned). Poor man's JGit migration is the escape hatch for v2.
- **Token storage / Play policy:** GitHub token is sensitive → EncryptedSharedPreferences + no logging; disclose in Data safety form; PAT fallback keeps OAuth review from blocking release.
- **Corruption on failed push:** all pushes are commit-atomic via Data API for multi-file; single-file push keeps local `sha` only on 201/200; otherwise mark dirty and retry.
- **No iCloud users:** Android v1 cannot sync iCloud-only repos — in onboarding, detect and explain "create a GitHub repo via Mac Settings → Sync → GitHub" with link.

## Open Questions (need your input — local discovery cannot answer)

### Product / Scope
1. **Repo layout:** Do you have a sample Reflect GitHub repo (or a fresh Mac-generated one) I can inspect? Exact paths (`*.md` at root vs `notes/`), frontmatter keys, `[[wikilink]]` vs `[text](note-id)` syntax, and attachment handling determine the parser. If not, I'll generate one from `reflect-open` and treat that as source of truth.
2. **Feature cut for v1:** Is this the right MVP? Proposed: list + read + edit + create + delete + rename + search + daily note + pull-to-refresh/sync. Deferred: graph view, backlinks panel, tags filter, attachments/preview, templates, slash commands, AI chat. What would you add or cut?
3. **Daily notes:** Should `Today` create/open `YYYY-MM-DD.md` in a `daily/` folder matching the Mac CLI's `reflect today`, or reuse the existing daily path from the repo?
4. **Attachments / images:** GitHub repos often store assets as `assets/…`. Should v1 show images inline and allow capturing a photo → commit to `assets/`, or defer attachments to v2?

### Auth & GitHub
5. **Auth method:** Do you want me to register a GitHub OAuth App under your org (needs callback URL + homepage), or ship v1 with fine-grained PAT only and add OAuth after TestFlight/closed track feedback?
6. **Private vs public + org repos:** Must v1 support GitHub Enterprise Cloud or only `github.com`? Any SSO / SAML constraints?
7. **Commit identity:** What should Android commits look like? e.g., `author: user` + message `reflect-android: update <note title>` — or keep the desktop's commit message format?

### Platform
8. **Min devices:** minSdk 26 (Android 8.0) covers 95%+ devices. Do you need to support Android 7 (minSdk 24) or is 26 OK? Target device for perf testing?
9. **Distribution:** Play Store closed track vs direct APK/F-Droid for v1? Do you have a Play Console org and signing key story?
10. **Brand / design:** Should Android follow the Mac app's visual language exactly (copy its typography/colors), or adopt Material 3 with Reflect accent? Any Figma or screenshots to match?
11. **Offline conflict UX:** For same-file conflicts, is "keep both (create `Note (conflict).md`)" acceptable as default, or do you want an explicit diff/merge UI in v1?

### Operations
12. **Monorepo vs standalone:** Should the Android project live inside `reflect-open` (e.g., `android/` folder, shared docs), or in its own `reflect-android` repo that depends only on the GitHub contract?
13. **Telemetry:** Do you want any analytics (e.g., just sync success/failure counts) or strictly no telemetry for this local-first audience?

---

## Addendum — 2026-08-06: User Input Incorporated (from `~/Source/reflect-notes` inspection)

**User answers received:**
- ✅ Sample repo provided at `~/Source/reflect-notes` (inspected — see Contract below)
- ✅ MVP: **no** graph/backlinks/tags (defer to v2); **yes** attachments with inline preview + camera capture → `assets/`
- ✅ `github.com` only (no Enterprise), register OAuth App
- ✅ No telemetry
- ✅ Material 3 + Reflect accent (not exact Mac clone)
- ✅ Prefers **direct APK sideload** without Play Services — asked if possible

### Updated Contract — Grounded on Real Repo

`~/Source/reflect-notes` (`origin: https://github.com/joelwreed/reflect-notes`, 21 root notes + extras, `main` clean):

```
.gitignore → /.reflect/  (+ .DS_Store, *.swp etc — .reflect is rebuildable local index, never committed)
*.md at repo root       — 21 files, each note is a root-level markdown file
daily/YYYY-MM-DD.md      — e.g. daily/2026-07-28.md (2 lines, no frontmatter id — daily notes are lighter)
notes/how-to-use-reflect.md — pinned doc, canonical syntax reference
assets/pasted-*.png      — referenced as ![](assets/pasted-1785183966286.png) but not present on disk (not yet pushed or gitignored) — image support is real but sparse
```

**Per-note file verified:**
```md
---
id: 01kxp66n18p7vt6b5rsmd1taqy   # ulid, always present except daily stub inspected
aliases:                        # optional, seen once
  - OLLI - University of Pitt
---
# Title as H1

- Type: #person / #meeting etc (tag-like)
- Email: ...
- Body markdown, wikilinks [[Wiki Links]] per notes/how-to-use-reflect.md
- Images: ![](assets/...)
```
- Title = first `# ` heading; `id` is canonical identity (file rename ≠ identity change).
- Wikilinks use `[[Title]]` — body contains zero `[[` in samples except the doc itself, but syntax is confirmed.
- Commit messages are freeform ("Update notes", "Add daily note") — no enforced format; git log shows no `reflect:` prefix.
- Branch is `main`; sync is plain git push/pull to `origin`.

**Implication for Android:**
- Local store must key on `id` (from frontmatter) not filename; filename is derived from title slug but can drift.
- `daily/` notes may lack `id` — treat path `daily/YYYY-MM-DD.md` as id for those.
- Repo layout is **flat + daily/ + notes/ + assets/** — no `notes/` shroud for personal notes; "There are no folders." holds for user notes, but `daily/` and `notes/` are the two blessed subdirs.

### Locked Decisions (updated)

| # | Was | Now | Note |
|---|-----|-----|------|
| Scope | Graph/backlinks/tags TBD | **Deferred to v2** — v1 is list/read/edit/create/delete/search + daily + attachments preview/capture | User confirmed |
| Attachments | Question | **In for MVP:** inline `![](assets/…)` preview (Coil), camera capture → `assets/pasted-<epoch>.jpg/png`, gallery pick → copy to `assets/` | New |
| Auth | OAuth vs PAT | **OAuth App (github.com only)** + PAT fallback for dev | User confirmed github.com only |
| Telemetry | Question | **None** — no Firebase Analytics/Crashlytics by default; optional ACRA file log only if user opts in later | User confirmed |
| Design | Question | **Material 3 + Reflect accent** — extract accent from Mac app (likely warm neutral + amber/blue); not pixel-perfect clone | User confirmed |
| Distribution | Question | **Direct APK (sideload) primary** — no Play Services dependency; Play closed track as optional secondary | See APK answer below |

### APK Without Play Services — Yes, Fully Possible

You do **not** need Play Services or the Play Store to install on Android.

- **How:** `assembleRelease` produces a signed `app-release.apk` that users install via "Allow from this source" (sideload), or via `adb install`. Distribution can be **GitHub Releases** on `team-reflect/reflect-open` or a new `reflect-android` repo — users download APK, tap to install. No Google account required.
- **What to avoid to stay de-googled:** Don't add `play-services-*`, `firebase-*`, `com.google.android.gms`, or Play Billing. Use only AOSP + AndroidX. That means: no Firebase Crashlytics (use local log + optional user-sent bug report), no Play In-App Updates (use manual "Check for updates" → GitHub Releases API), no GCM/FCM push.
- **Signing:** You need a `release.keystore` (generated locally, `gradle.properties` `storePassword`); keep it out of git, back it up. Play App Signing is optional only if you later publish to Play.
- **Updates:** Since no Play, ship an in-app `UpdateChecker` that polls `api.github.com/repos/<owner>/<repo>/releases/latest` and prompts "Download APK" → uses `PackageInstaller`. Or just tell users to re-download — acceptable for v1.
- **F-Droid (optional):** If you want a store without Google, F-Droid builds from source and distributes updates — compatible with the same APK, zero Play dependency.
- **Tradeoff:** No auto-update, no Play Protect review badge, and Android 13+ shows a scarier "unknown app" prompt — but for Reflect's technical audience this is normal (Obsidian, Signal APK do the same).

**Recommendation:** Build **two flavors**: `gmsFree` (default, no Play deps, GitHub Releases) + optional `play` flavor if you later want Play closed track — same codebase, single `build.gradle` `flavorDimensions`. v1 ships `gmsFree` only.

### Resolved — 2026-08-06: Defaults Confirmed, Project Location = `specular`

- **Commit identity (Q7):** ✅ `Update <title>` / `Update N notes`, author = OAuth user
- **minSdk (Q8):** ✅ **26 (Android 8.0)**
- **Conflict UX (Q11):** ✅ Conflict copy `Note (conflict YYYY-MM-DD).md` + Keep mine/theirs/both banner, no diff UI v1
- **Monorepo vs standalone (Q12):** ✅ **Use `~/Source/specular` as Android project root** (per user instruction)
- **Daily note template (Q3):** ✅ `daily/YYYY-MM-DD.md` with auto `id`, reusing existing `daily/` folder
- **Brand accent (Q10):** ✅ Material 3 + Reflect accent, interim amber `#D97706` + neutral `#1A1A1E`

**Next step:** Finalize `docs/reflect-contract.md` and scaffold Android project in `specular/` per this approved plan.

*Approved: 2026-08-06 — all open questions resolved. Plan is decision-complete.*

## Implementation Status — 2026-08-08

The local-first note stack, Markdown rendering/editing, offline search, attachment
capture/preview, GitHub Contents API pull/push, durable dirty/delete/rename state,
conflict-copy preservation, lifecycle/manual/periodic sync, and direct-APK project
setup are implemented.

The following approved plan items were completed on 2026-08-08:

- Manual **Sync now** and pull-to-refresh from the note list.
- PAT-based repository picker: it lists repositories accessible to the entered
  token and validates that the selected default branch contains Markdown notes
  before it can be saved.
- Editor polish: Markdown shortcuts, `[[wikilink]]` suggestions from the local
  index, and a Today action that opens or creates `daily/YYYY-MM-DD.md` with an id.

### Remaining Open Implementation Items

- **OAuth App + PKCE:** register the GitHub OAuth App, supply a real client id,
  and implement browser authorization, redirect validation, and token exchange.
  PAT remains the working authentication path.
- **Conflict resolution UX:** conflict copies are created safely, but the approved
  Keep mine / Keep theirs / Keep both actions have not been implemented.
- **Batch atomic commits:** multi-file changes currently use sequential Contents
  API requests; Git Data create-tree/create-commit/update-ref batching remains open.
- **Large-repository hardening:** handle truncated trees/pagination, add a large
  file guard, and measure the 2k-note cold-start and incremental-sync targets.
- **Sync error UX:** show specific rate-limit, expired-auth, private-repository,
  and oversized-file guidance rather than only the current generic error message.
- **Settings completion:** configurable periodic-sync policy, intentional
  repository-switch/cache-clear flow, and any needed migration UI remain open.
- **Release readiness:** add instrumented and screenshot tests, CI (build/lint/test),
  real-device/private-repo and airplane-mode validation, signing/release
  instructions, an import guide, and `SYNC.md`.
