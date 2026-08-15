# Specular Product Roadmap

**Drafted:** 2026-08-15  
**Status:** Proposed

## Product Direction

Specular is a private, local-first Markdown notebook. Markdown files are the
canonical library; GitHub is an optional synchronization and backup mechanism,
not a required hosted workspace. The roadmap should strengthen that position:
help people capture information quickly, find it reliably, and turn notes into
action without making their data dependent on a proprietary service.

The product already supports offline notes, folders, pinned notes, daily notes,
global Markdown checklists, wiki links, image attachments, GitHub sync,
portable backups, voice transcription, and optional AI summaries. The most
valuable missing capabilities are retrieval, structure, and richer capture—not
a wholesale rewrite into a collaborative document suite.

## Principles

1. **Keep Markdown portable.** New metadata and features must either have a
   useful Markdown representation or remain rebuildable local index data. Do
   not make notes unreadable outside Specular.
2. **Local first, server optional.** Core capture, browsing, search, and task
   workflows must work offline. Third-party AI and hosted services remain
   explicit opt-ins.
3. **Improve recall before adding complexity.** Tags, search, links, and
   simple saved views offer more value to most users than a broad database or
   collaboration platform.
4. **Make automation inspectable.** Reminders, templates, AI-derived data, and
   conflict resolution must show users what will happen and preserve originals.
5. **Ship across the existing Android and macOS clients.** Add a capability
   only when its platform behavior, backup/sync semantics, and accessibility
   have been considered.

## Roadmap

### Foundation — Harden sync and ship reliably

**Outcome:** The existing local-first and GitHub-sync workflow is convenient,
observable, and proven at realistic library sizes before the product adds more
data and platforms.

- Register a GitHub OAuth App and implement authorization-code authentication
  with PKCE. Keep fine-grained PAT entry for development and environments where
  OAuth is unavailable.
- Show scheduled retry timing and sync status after Android WorkManager applies
  exponential backoff.
- Benchmark a representative 2,000-note library, targeting an interactive
  list in under two seconds on cold start and Wi-Fi incremental sync in under
  five seconds.
- Add large-file guards. If full-tree traversal does not meet the benchmark,
  evaluate pagination and lazy download without weakening offline access to
  already-opened notes.
- Add Android integration coverage for onboarding, editing, conflict recovery,
  and attachment sync; retain the current parser, repository, and mocked API
  tests.
- Record manual verification of concurrent desktop/mobile edits and offline
  edit/reconnect behavior.
- Add GitHub Actions for analysis, tests, and debug APK builds. Establish
  signing-key custody before adding a signed-release workflow.
- Produce a signed, GMS-free APK and an install/update guide for GitHub
  Releases. Decide separately whether an optional Play distribution track is
  warranted.

**Why first:** Later phases add metadata, attachments, and cross-device use.
They should build on a sync path that is observable, measured, and releasable.

### Phase 1 — Find and reconnect notes

**Outcome:** A user can retrieve a note or concept quickly, even when they do
not remember its folder or exact wording.

- Add first-class Markdown tags (`#tag`) with a local tag index.
- Filter note lists by tag, folder, note type, date, pin/archive state, and
  task state.
- Add saved searches / smart views, including useful defaults such as Recent,
  Untagged, and Notes with open tasks.
- **Implemented (2026-08-15):** Upgrade search from a title/body substring
  match to ranked full-text search with highlighted matches, phrase search, and
  All/Titles/Body scopes.
- Add a backlinks panel for wiki links and Markdown note links, including
  unlinked title mentions where practical.
- Optionally add a lightweight local graph only after backlinks and filters
  provide clear value.

**Why now:** Specular can create and link notes, but users cannot yet see what
links to a note or organize a growing library beyond folders, pins, and basic
search. Backlinks and relationship views are established strengths of
[Obsidian](https://obsidian.md/help/Plugins/Backlinks).

**Portable representation:** tags stay in Markdown. Search indexes, saved view
definitions, and link indexes are local/rebuildable.

### Phase 2 — Repeatable notes and actionable tasks

**Outcome:** Common workflows—meetings, daily planning, projects, and
follow-ups—need less repeated setup and produce usable next actions.

- Add user-editable templates for notes, meetings, people, and journals.
- Support date-aware recurring templates for daily, weekly, and monthly notes.
- Add task metadata: due date, reminder, priority, and recurrence.
- Add task views for Today, Upcoming, Overdue, and Completed, while retaining
  plain Markdown checkboxes as the base format.
- Let users link a task back to its source note and filter tasks by tag/folder.
- Provide a template picker in note creation instead of expanding the primary
  navigation with more fixed note types.

**Why now:** Global checklists are already present; task metadata and templates
make that capability useful for planning without requiring a Notion-style
workspace. Recurring templates are a proven pattern for regular meetings and
reviews; see [Notion's template documentation](https://www.notion.com/help/database-templates?slug=database-templates).

**Portable representation:** use a documented Markdown-compatible convention
for task dates and recurrence. Keep reminder delivery state local, rebuildable,
and separate from note content.

### Phase 3 — Capture source material, not just text

**Outcome:** Users can collect research, documents, and meeting material in a
note without losing context or ownership.

- Add a web clipper/share-target workflow that saves a clean excerpt, page
  title, source URL, capture date, and optional full-page snapshot.
- Support general attachments, starting with PDFs and common office/document
  types; keep them alongside the Markdown library and sync them deliberately.
- Add document scanning, image OCR, and search over extracted text where the
  platform supports it.
- Add screenshot capture/import and automatic source-link attribution on web
  paste where possible.
- Preserve meeting recordings as optional first-class note attachments with
  playback and a timestamped transcript, rather than retaining only the final
  transcript.

**Why now:** Image attachment and speech-to-text exist, but research and
meeting workflows still lose the original source. Mainstream notebook apps
support mixed media and search in images/recordings; for example,
[OneNote searches text, handwriting, images, and recorded speech](https://support.microsoft.com/en-US/OneNote/onenote-help-and-learning/search-notes-in-onenote).

**Guardrails:** large attachments need clear sync size controls, Wi-Fi policy,
storage usage, export behavior, and a local-only option. Never upload audio or
document content without the user choosing sync.

### Phase 4 — Trust, history, and sharing

**Outcome:** Users can recover from mistakes confidently and can selectively
work with others when their workflow needs it.

- Add a local trash with a retention period and restore flow.
- Show per-note version history, diffs, and restore actions. Surface GitHub
  commits when configured, but do not require GitHub for local history.
- Replace conflict-copy-only handling with a conflict review screen that can
  compare local, remote, and resolved versions before preserving a copy.
- Add explicit export/share actions for Markdown, rendered PDF, text, and
  attachments.
- Evaluate lightweight sharing first: shareable read-only bundles or a
  GitHub-backed shared repository with documented expectations.
- Defer real-time co-editing, comments, mentions, permissions, and presence
  until there is validated demand; these features require a fundamentally
  different synchronization and identity model.

**Why now:** Current synchronization preserves data safely, but it does not
give users a clear recovery or resolution interface. Collaboration is valuable
but should not compromise local ownership to mimic shared-workspace products.

### Phase 5 — Broaden the note-taking surface

**Outcome:** Specular is available where people take notes and supports visual
thinking when that is core to their work.

- Prioritize iPhone/iPad support, then assess Windows, Linux, and web based on
  demand and the ability to retain local-first semantics.
- Add stylus handwriting, sketching, image/PDF annotation, and handwriting
  recognition for touch-focused platforms.
- Explore an open, file-backed canvas format for visual note organization.
- Consider a graph and canvas as complementary ways to navigate existing
  Markdown notes, not as replacement document formats.

**Why later:** This improves reach and supports important workflows, but is
less broadly valuable than retrieval, templates, tasks, and capture. Obsidian's
[Canvas](https://obsidian.md/help/Plugins/Canvas) is a useful example of a
visual layer stored in an open file format.

## Explicit Non-Goals for the Near Term

- Recreating a full Notion-style relational database, formulas, boards, or
  enterprise workspace model.
- Requiring a Specular account, cloud server, analytics service, or proprietary
  sync format.
- Adding real-time multiplayer editing before local history and clear sharing
  semantics are in place.
- Replacing Markdown notes with a closed rich-text document format.

## Decision Gates

Before starting each phase, confirm the following:

| Phase | Decision gate |
|---|---|
| Foundation | OAuth, retry reporting, benchmark results, Android integration coverage, and signing/release ownership have an approved delivery plan. |
| 1 | Tags and saved views have a documented Markdown/local-index split; search performance is measured on a large library. |
| 2 | Task metadata syntax is portable and existing Markdown checklists remain unchanged. |
| 3 | Attachment size, encryption/privacy, sync, export, and deletion behavior are specified before implementation. |
| 4 | Local versioning has a retention and storage policy; sharing has an explicit trust and identity model. |
| 5 | Target-platform demand and offline/sync support justify the maintenance cost. |

## Measures of Success

- A user can find an existing note from a concept, tag, link, or partial phrase
  in a few seconds.
- A recurring meeting or planning note can be created from a template with no
  manual boilerplate.
- A task captured in any note reliably appears in the appropriate action view
  and can notify the user locally.
- Imported source material remains attributable, searchable where supported,
  exportable, and under the user's control.
- A user can inspect and recover a mistaken edit or synchronization conflict
  without manipulating repository files directly.
