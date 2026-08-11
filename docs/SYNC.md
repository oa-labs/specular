# GitHub Sync

Specular synchronizes a local Markdown library directly with a GitHub repository that follows the [Reflect sync contract](reflect-contract.md). It does not use a Specular or Reflect server.

## Before you begin

- Use a repository on `github.com`; public and private repositories work.
- Create a fine-grained GitHub personal access token with **Contents: Read and write** permission for that repository.
- The repository must already contain at least one supported Markdown note. Specular supports notes at the root and under `notes/`, and daily notes under `daily/`.

OAuth is planned but is not currently available. A personal access token is the supported sign-in method.

## Connect a repository

1. Open **Settings** in Specular.
2. Enter the GitHub personal access token.
3. Choose **Choose repository**, select the desired repository, and allow Specular to validate that it contains Markdown notes.
4. Select **Save and sync**.

The first sync imports remote notes and supported attachments into the app's private storage. Existing local notes are preserved; if they conflict with a remote file, Specular creates a conflict copy rather than overwriting them.

## What syncs

| Repository path | Treatment |
|---|---|
| `*.md` and `notes/**/*.md` | Notes |
| `daily/YYYY-MM-DD.md` | Daily notes |
| `attachments/**`, `assets/**` | Image attachments |
| `assets/*.reflect.md` | Ignored metadata sidecars |
| `.reflect/` | Ignored local Reflect cache |

Specular preserves note frontmatter and uses its `id` as the stable identity. For daily notes without frontmatter, the relative daily path is the identity. New camera/gallery images are added to `attachments/` and inserted as standard relative Markdown image links.

## How synchronization stays safe

Edits are saved locally first, even without a network connection. Each changed note, rename, deletion, and attachment is marked dirty in the local database. When network is available, Specular pulls remote changes before it pushes local ones.

Uploads use GitHub's Git Data API to create one commit for all pending changes. The branch ref is updated without force, so the app cannot silently replace a concurrent remote commit.

If the same note changed locally and remotely, Specular keeps both:

1. It saves the local content as `Title (conflict YYYY-MM-DD).md` (with a unique suffix if necessary).
2. It applies the remote version at the original path.
3. It uploads the conflict note on the next successful sync.

Review the conflict note, merge the desired content manually, and delete the extra note when it is no longer needed.

## When sync runs

- Pull-to-refresh and the app's sync action run a foreground sync.
- The app schedules one-off network work after local changes.
- Choose a background cadence in **Settings**, from every 15 minutes to daily. Android WorkManager may defer this work for battery, connectivity, or background-execution reasons.

## Change repositories or rebuild the local mirror

Specular never applies a newly selected repository on top of the existing local mirror. In **Settings**, choose the new repository and select **Switch repository**. Specular validates it first, then requires confirmation before it removes the device's local notes, attachments, search index, and pending sync state. The GitHub repositories are never changed by this action.

Use **Clear local sync cache** to discard the current device mirror and import the configured repository again. Both actions warn when there are unsynced local edits; those edits must be synced first or will be lost.

You can always keep editing offline. The dirty state remains until GitHub acknowledges the exact local revision.

## Troubleshooting

| Message or symptom | What to check |
|---|---|
| `GitHub token is invalid or expired` | Create or paste a valid fine-grained PAT with repository Contents read/write access. |
| `GitHub repository or branch was not found` | Confirm the owner, repository, token access, and default branch. Private repositories intentionally look like 404s when the token lacks access. |
| `GitHub denied access or rate-limited this sync` | Verify token permissions, then wait for GitHub's rate limit to reset before retrying. Your local changes remain safe. |
| `Network unavailable` | Continue working locally and sync when the device reconnects. |
| Conflict note appears | Both local and remote versions were retained. Merge the content manually, save, then sync. |
| An image is missing | Confirm the Markdown reference is repository-relative and that the file is under `attachments/` or `assets/`. |

## Privacy and credentials

The GitHub token is stored using Android secure storage. It is sent only to GitHub's API for repository access. Specular includes no telemetry, Firebase, or Play Services dependencies.
