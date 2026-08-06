# Reflect GitHub Sync Contract — Grounded on ~/Source/reflect-notes (2026-08-06)

This is the source of truth for the Android ↔ Reflect sync. Derived from a live repo at `~/Source/reflect-notes` (`origin https://github.com/joelwreed/reflect-notes`, branch `main`).

## Repo Layout

| Path | Meaning | Example |
|------|---------|---------|
| `*.md` at root | User notes — flat, "There are no folders" | `barry-kaufman.md`, `virtual-board-meeting-july-16th-2026.md` (21 at last count) |
| `daily/YYYY-MM-DD.md` | Daily notes | `daily/2026-07-28.md` |
| `notes/how-to-use-reflect.md` | Pinned help doc, also the wikilink syntax spec | — |
| `assets/pasted-*.png` | Image attachments referenced via markdown | `![](assets/pasted-1785183966286.png)` in `olli-university-…` |
| `/.reflect/` | Local rebuildable index/cache — **never committed** (`.gitignore`) | — |
| `.gitignore` | Also ignores `.DS_Store`, `*.swp`, `Thumbs.db` | — |

## Per-Note File Format (verified)

```md
---
id: 01kxp66n18p7vt6b5rsmd1taqy
# optional:
aliases:
  - OLLI - University of Pitt
---
# Title (H1, first heading is title)

- Type: #person | #meeting | …
- Email: …
- Phone: …

Body markdown — may contain [[Wiki Links]] and ![](assets/…)
```

- `id` is ULID-like, canonical identity. Filename is a slug of title and may change — **key storage on `id`**, not filename.
- `aliases` is rare/optional.
- Title = first `# ` line.
- Daily stub (`daily/2026-07-28.md`) observed without frontmatter — treat path as id for dailies if no `id` present; on creation Android will write frontmatter with generated `id`.
- Wikilink syntax: `[[Title]]` per `notes/how-to-use-reflect.md`. No `[[` found in bodies yet but spec is confirmed.
- Image syntax: standard markdown `![](assets/…)`.

## Git Behavior

- Branch: `main`, remote `origin` is GitHub HTTPS.
- Commit messages are freeform (`Update notes`, `Add daily note for 2026-07-28`) — no prefix required. Android will use `Update <title>` / `Update N notes`.
- Sync is plain git push/pull; Android mirrors this via GitHub REST Contents/Data API (no custom Reflect server).

## Android Implications

- Local DB (Room) primary key = `id` (or `daily/YYYY-MM-DD` for dailies without id). Maintain `filename ↔ id` index and `lastRemoteSha` per file for ETag/sha concurrency.
- Search index (FTS) over title + body; links are not resolved in v1 (backlinks deferred).
- Attachments: on capture, write to `assets/pasted-<epoch>.jpg` and reference via `![](assets/…)`. Binary files are pushed as base64 via Contents API.
- Conflicts: if local dirty + remote `sha` changed, write `Name (conflict YYYY-MM-DD).md` and surface banner.
