package com.specular.android.sync

import android.util.Log
import com.specular.android.data.local.FileStore
import com.specular.android.data.local.AttachmentDao
import com.specular.android.data.local.AttachmentEntity
import com.specular.android.data.local.FrontmatterParser
import com.specular.android.data.local.MarkdownAttachmentResolver
import com.specular.android.data.local.NoteDao
import com.specular.android.data.local.NoteEntity
import com.specular.android.data.local.NoopAttachmentDao
import com.specular.android.data.local.NoteStoreLock
import com.specular.android.data.local.TodoIndex
import com.specular.android.data.remote.GitHubApi
import com.specular.android.data.remote.GitHubAuth
import com.specular.android.data.remote.PutContentRequest
import com.specular.android.data.remote.DeleteContentRequest
import com.specular.android.widget.TodoWidgetUpdater
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Base64
import java.util.UUID
import retrofit2.HttpException
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Offline-first sync engine per plan:
 * - Pull: GET tree sha, diff vs local lastRemoteSha, download changed blobs
 * - Push: PUT contents per dirty file with optimistic sha; on 409 create conflict copy
 * See docs/reflect-contract.md and docs/plans/2026-08-06-android-github-sync.md
 */
@Singleton
class SyncEngine @Inject constructor(
    private val api: GitHubApi,
    private val auth: GitHubAuth,
    private val dao: NoteDao,
    private val fileStore: FileStore,
    private val noteStoreLock: NoteStoreLock = NoteStoreLock(),
    private val todoIndex: TodoIndex = TodoIndex(),
    private val attachmentDao: AttachmentDao = NoopAttachmentDao,
    private val todoWidgetUpdater: TodoWidgetUpdater? = null
) {
    sealed class Result {
        data object Success : Result()
        data class Error(val message: String) : Result()
        data object NotConfigured : Result()
    }

    suspend fun pull(): Result = noteStoreLock.withLock { pullLocked() }
        .also { todoWidgetUpdater?.requestUpdate() }

    private suspend fun pullLocked(): Result = withContext(Dispatchers.IO) {
        val header = auth.authHeader() ?: return@withContext Result.NotConfigured
        val owner = auth.repoOwner ?: return@withContext Result.NotConfigured
        val repo = auth.repoName ?: return@withContext Result.NotConfigured

        logInfo("Pull started repository=$owner/$repo")
        try {
            val branch = runSyncStage("pull:get repository") {
                api.getRepo(owner, repo, header).default_branch
            }
            val ref = runSyncStage("pull:get branch ref branch=$branch") {
                api.getRef(owner, repo, branch, header)
            }
            val tree = runSyncStage("pull:get tree") {
                api.getTree(owner, repo, ref.`object`.sha, header, recursive = 1)
            }
            logDebug("Pull tree loaded markdownCandidates=${tree.tree.count { isMarkdownNote(it) }}")

            val remoteMarkdownPaths = tree.tree
                .asSequence()
                .filter(::isMarkdownNote)
                .map { it.path }
                .toSet()

            for (entry in tree.tree) {
                if (!isMarkdownNote(entry)) continue
                val localAtPath = dao.getByPath(entry.path)
                // A locally requested deletion is authoritative until its remote
                // operation completes. Do not revive it during the pull phase.
                if (localAtPath?.isPendingDeletion == true) continue
                // A matching remote SHA means the remote has not changed. Keep a dirty
                // local copy intact so the subsequent push can publish it.
                if (localAtPath?.lastRemoteSha == entry.sha) continue

                val contentResponse = runSyncStage("pull:download path=${entry.path}") {
                    api.getContent(owner, repo, entry.path, header, ref = branch)
                }
                val raw = contentResponse.content?.let { b64 ->
                    String(Base64.getDecoder().decode(b64.replace("\n", "")), Charsets.UTF_8)
                } ?: continue
                val parsed = FrontmatterParser.parse(entry.path, raw)
                val remoteId = FrontmatterParser.identityFor(entry.path, parsed.id)
                val localWithSameId = dao.getById(remoteId)

                // A local rename creates the destination first, then deletes this old
                // path. Until that happens, the old remote file is expected and must
                // not be mistaken for a remote rename in the opposite direction.
                if (localWithSameId?.isDirty == true &&
                    localWithSameId.pendingRenameFromPath == entry.path
                ) {
                    continue
                }

                // The stable frontmatter id identifies a remote rename. A clean local
                // file can simply move. If it has local edits, retain those as a dirty
                // conflict copy and make the renamed remote file canonical.
                if (localWithSameId != null && localWithSameId.path != entry.path) {
                    if (localWithSameId.isDirty) {
                        preserveLocalAsConflict(localWithSameId)
                    } else {
                        fileStore.delete(localWithSameId.path)
                    }
                    persistRemote(entry.path, entry.sha, raw, parsed)
                    continue
                }

                // Concurrent edits to the same path keep the remote version at its
                // canonical path and turn the local version into a separately
                // pushable conflict note. This prevents an endless sha-mismatch loop.
                if (localAtPath != null && localAtPath.isDirty && localAtPath.lastRemoteSha != entry.sha) {
                    preserveLocalAsConflict(localAtPath)
                    persistRemote(entry.path, entry.sha, raw, parsed)
                    continue
                }

                persistRemote(entry.path, entry.sha, raw, parsed)
            }
            pullReferencedAttachments(tree.tree, owner, repo, header, branch)
            reconcileRemoteRemovals(remoteMarkdownPaths)
            logInfo("Pull completed")
            Result.Success
        } catch (e: Exception) {
            logSyncFailure("pull", e)
            Result.Error(userFacingSyncError("pull", e))
        }
    }

    suspend fun push(): Result = noteStoreLock.withLock { pushLocked() }

    private suspend fun pushLocked(): Result = withContext(Dispatchers.IO) {
        val header = auth.authHeader() ?: return@withContext Result.NotConfigured
        val owner = auth.repoOwner ?: return@withContext Result.NotConfigured
        val repo = auth.repoName ?: return@withContext Result.NotConfigured
        logInfo("Push started repository=$owner/$repo")
        try {
            val branch = runSyncStage("push:get repository") {
                api.getRepo(owner, repo, header).default_branch
            }
            val pendingDeletions = runSyncStage("push:load pending deletions") {
                dao.getPendingDeletions()
            }
            val pendingRenames = runSyncStage("push:load pending renames") {
                dao.getPendingRenames()
            }
            val referencedAttachments = dao.getAllForTodoIndex()
                .asSequence()
                .filterNot { it.isPendingDeletion }
                .flatMap { MarkdownAttachmentResolver.referencedPaths(it.path, it.rawMarkdown).asSequence() }
                .toSet()
            val dirtyAttachments = runSyncStage("push:load dirty attachments") {
                attachmentDao.getDirty().filter { it.path in referencedAttachments }
            }
            val dirty = runSyncStage("push:load dirty notes") { dao.getDirty() }
                .filterNot { it.isPendingDeletion }
            if (dirty.isEmpty() && pendingDeletions.isEmpty() && pendingRenames.isEmpty() && dirtyAttachments.isEmpty()) {
                logInfo("Push skipped: no dirty notes")
                return@withContext Result.Success
            }
            logDebug("Push queued notes=${dirty.size} attachments=${dirtyAttachments.size} deletions=${pendingDeletions.size} renames=${pendingRenames.size}")
            var failedPushes = 0
            // Markdown must not be published before the binary it references.
            for (attachment in dirtyAttachments) {
                val bytes = fileStore.readBytes(attachment.path)
                    ?: return@withContext Result.Error("Attachment ${attachment.path} is missing locally.")
                try {
                    val response = api.putContent(
                        owner, repo, attachment.path, header,
                        PutContentRequest(
                            message = "Upload attachment ${attachment.path.substringAfterLast('/')}",
                            content = Base64.getEncoder().encodeToString(bytes),
                            sha = attachment.lastRemoteSha,
                            branch = branch
                        )
                    )
                    attachmentDao.upsert(
                        attachment.copy(lastRemoteSha = response.content?.sha, isDirty = false)
                    )
                } catch (ex: Exception) {
                    logPushFailure(attachment.path, ex)
                    return@withContext Result.Error(userFacingPushError(ex))
                }
            }
            for (e in pendingDeletions) {
                // A note created and deleted before its first push has no remote
                // counterpart, so completing its local deletion is sufficient.
                if (e.lastRemoteSha == null) {
                    runSyncStage("push:discard unsynced deletion path=${e.path}") {
                        fileStore.delete(e.path)
                        dao.deleteNoteAndTodos(e.id)
                    }
                    continue
                }
                try {
                    logDebug("Push deleting path=${e.path}")
                    api.deleteContent(
                        owner, repo, e.path, header,
                        DeleteContentRequest(
                            message = "Delete ${e.title}",
                            sha = e.lastRemoteSha,
                            branch = branch
                        )
                    )
                    runSyncStage("push:persist deletion path=${e.path}") {
                        fileStore.delete(e.path)
                        dao.deleteNoteAndTodos(e.id)
                    }
                } catch (ex: Exception) {
                    // A 404 means another client already removed this file. Treat it
                    // as a completed deletion; other failures remain pending to retry.
                    if ((ex as? HttpException)?.code() == 404) {
                        runSyncStage("push:complete already-deleted path=${e.path}") {
                            fileStore.delete(e.path)
                            dao.deleteNoteAndTodos(e.id)
                        }
                        continue
                    }
                    failedPushes++
                    logPushFailure(e.path, ex)
                    val statusCode = (ex as? HttpException)?.code()
                    if (statusCode == 409 || statusCode == 422) continue
                    return@withContext Result.Error(userFacingPushError(ex))
                }
            }
            for (e in dirty) {
                val raw = runSyncStage("push:read local path=${e.path}") {
                    fileStore.read(e.path) ?: e.rawMarkdown
                }
                val b64 = Base64.getEncoder().encodeToString(raw.toByteArray(Charsets.UTF_8))
                try {
                    logDebug("Push uploading path=${e.path}")
                    val resp = api.putContent(
                        owner, repo, e.path, header,
                        PutContentRequest(
                            message = "Update ${e.title}",
                            content = b64,
                            sha = e.lastRemoteSha,
                            branch = branch
                        )
                    )
                    val newSha = resp.content?.sha
                    runSyncStage("push:persist success path=${e.path}") {
                        fileStore.write(e.path, raw)
                        dao.upsert(e.copy(lastRemoteSha = newSha, isDirty = false, isConflict = false))
                    }
                } catch (ex: Exception) {
                    failedPushes++
                    logPushFailure(e.path, ex)
                    // 409/422 means sha mismatch — leave dirty for next pull to create conflict
                    val statusCode = (ex as? HttpException)?.code()
                    if (statusCode == 409 || statusCode == 422) {
                        continue
                    }
                    return@withContext Result.Error(userFacingPushError(ex))
                }
            }
            // A rename is intentionally non-atomic with the Contents API: create the
            // destination first, then remove the old path. The pending fields survive
            // process death between those requests and make the delete retryable.
            for (e in dao.getPendingRenames()) {
                val oldPath = e.pendingRenameFromPath ?: continue
                val oldSha = e.pendingRenameFromSha ?: continue
                try {
                    logDebug("Push completing rename oldPath=$oldPath newPath=${e.path}")
                    api.deleteContent(
                        owner, repo, oldPath, header,
                        DeleteContentRequest("Rename ${e.title}", oldSha, branch)
                    )
                    dao.upsert(e.copy(pendingRenameFromPath = null, pendingRenameFromSha = null))
                } catch (ex: Exception) {
                    // A desktop client may already have removed the old path.
                    if ((ex as? HttpException)?.code() == 404) {
                        dao.upsert(e.copy(pendingRenameFromPath = null, pendingRenameFromSha = null))
                        continue
                    }
                    failedPushes++
                    logPushFailure(oldPath, ex)
                    val statusCode = (ex as? HttpException)?.code()
                    if (statusCode == 409 || statusCode == 422) continue
                    return@withContext Result.Error(userFacingPushError(ex))
                }
            }
            if (failedPushes > 0) {
                return@withContext Result.Error(
                    "Some notes could not be pushed because the remote changed. " +
                        "Review the conflict copies and try syncing again."
                )
            }
            logInfo("Push completed")
            Result.Success
        } catch (e: Exception) {
            logSyncFailure("push", e)
            Result.Error(userFacingSyncError("push", e))
        }
    }

    suspend fun sync(): Result = noteStoreLock.withLock {
        logInfo("Sync started")
        val pullResult = pullLocked()
        if (pullResult is Result.Error || pullResult is Result.NotConfigured) {
            logWarn("Sync stopped after pull result=$pullResult")
            return@withLock pullResult
        }
        val pushResult = pushLocked()
        logInfo("Sync completed result=$pushResult")
        pushResult
    }.also { todoWidgetUpdater?.requestUpdate() }

    private fun logPushFailure(path: String, error: Exception) {
        logSyncFailure("push:upload path=$path", error)
    }

    private suspend fun persistRemote(
        path: String,
        remoteSha: String,
        raw: String,
        parsed: FrontmatterParser.Parsed
    ) {
        runSyncStage("pull:persist path=$path") {
            fileStore.write(path, raw)
            val id = FrontmatterParser.identityFor(path, parsed.id)
            // Pinning is a local display preference, so retain it when this note is
            // refreshed from GitHub instead of encoding it in the Markdown file.
            val isPinned = dao.getById(id)?.isPinned ?: false
            val entity = NoteEntity(
                id = id,
                title = parsed.title,
                path = path,
                rawMarkdown = raw,
                body = parsed.body,
                aliases = parsed.aliases.toString(),
                snippet = FrontmatterParser.snippetOrEmpty(parsed.body, parsed.snippet),
                isDaily = path.startsWith("daily/"),
                isPinned = isPinned,
                lastRemoteSha = remoteSha,
                isDirty = false,
                isConflict = false
            )
            dao.upsertNoteAndReplaceTodos(entity, todoIndex.extract(entity.id, entity.body))
        }
    }

    /** Converts a locally edited file into a pushable conflict note. */
    private suspend fun preserveLocalAsConflict(note: NoteEntity) {
        val raw = fileStore.read(note.path) ?: note.rawMarkdown
        saveConflictCopy(note.path, raw, remoteSha = null, isDirty = true)
        dao.deleteNoteAndTodos(note.id)
        fileStore.delete(note.path)
    }

    private suspend fun saveConflictCopy(
        sourcePath: String,
        sourceRaw: String,
        remoteSha: String?,
        isDirty: Boolean
    ) {
        val conflictPath = nextConflictPath(sourcePath)
        val conflictId = "01" + UUID.randomUUID().toString().replace("-", "").take(24)
        val parsed = FrontmatterParser.parse(sourcePath, sourceRaw)
        val raw = parsed.rawFrontmatter?.let { frontmatter ->
            "---\n${FrontmatterParser.upsertIdInFrontmatter(frontmatter, conflictId)}\n---\n${parsed.body}"
        } ?: FrontmatterParser.generateFrontmatter(conflictId, parsed.aliases, parsed.snippet) + parsed.body
        val conflict = FrontmatterParser.parse(conflictPath, raw)
        fileStore.write(conflictPath, raw)
        val entity = NoteEntity(
            id = conflictId,
            title = "${conflict.title} (conflict)",
            path = conflictPath,
            rawMarkdown = raw,
            body = conflict.body,
            aliases = conflict.aliases.toString(),
            snippet = FrontmatterParser.snippetOrEmpty(conflict.body, conflict.snippet),
            isDaily = conflictPath.startsWith("daily/"),
            lastRemoteSha = remoteSha,
            isDirty = isDirty,
            isConflict = true
        )
        dao.upsertNoteAndReplaceTodos(entity, todoIndex.extract(entity.id, entity.body))
    }

    private suspend fun nextConflictPath(path: String): String {
        val stem = path.removeSuffix(".md")
        val date = java.time.LocalDate.now()
        var candidate = "$stem (conflict $date).md"
        var suffix = 2
        while (dao.getByPath(candidate) != null || fileStore.exists(candidate)) {
            candidate = "$stem (conflict $date $suffix).md"
            suffix++
        }
        return candidate
    }

    /** Removes clean local notes no longer present in the remote tree. */
    private suspend fun reconcileRemoteRemovals(remotePaths: Set<String>) {
        dao.getAllForTodoIndex().forEach { local ->
            if (local.path in remotePaths || local.isPendingDeletion || local.isConflict ||
                local.pendingRenameFromPath != null
            ) return@forEach
            if (local.isDirty) {
                logInfo("Pull preserving locally edited remote deletion path=${local.path}")
                preserveLocalAsConflict(local)
            } else {
                logDebug("Pull removing deleted remote path=${local.path}")
                fileStore.delete(local.path)
                dao.deleteNoteAndTodos(local.id)
            }
        }
    }

    /** Downloads only binary files referenced by locally indexed Markdown notes. */
    private suspend fun pullReferencedAttachments(
        treeEntries: List<com.specular.android.data.remote.TreeEntry>,
        owner: String,
        repo: String,
        header: String,
        branch: String
    ) {
        val remoteAttachments = treeEntries
            .asSequence()
            .filter { it.type == "blob" && MarkdownAttachmentResolver.isAttachmentPath(it.path) }
            .associateBy { it.path }
        val referenced = dao.getAllForTodoIndex()
            .asSequence()
            .filterNot { it.isPendingDeletion }
            .flatMap { MarkdownAttachmentResolver.referencedPaths(it.path, it.rawMarkdown).asSequence() }
            .toSet()

        for (path in referenced) {
            val remote = remoteAttachments[path] ?: continue
            val local = attachmentDao.getByPath(path)
            if (local?.lastRemoteSha == remote.sha && fileStore.exists(path)) continue
            // A locally captured attachment has not been uploaded yet; it wins over
            // an unexpected remote path collision rather than being overwritten.
            if (local?.isDirty == true) continue
            val response = runSyncStage("pull:download attachment path=$path") {
                api.getBlob(owner, repo, remote.sha, header)
            }
            val bytes = Base64.getDecoder().decode(response.content.replace("\n", ""))
            fileStore.writeBytes(path, bytes)
            attachmentDao.upsert(
                AttachmentEntity(
                    path = path,
                    mimeType = mimeTypeFor(path),
                    lastRemoteSha = remote.sha,
                    isDirty = false
                )
            )
        }
    }

    private fun isMarkdownNote(entry: com.specular.android.data.remote.TreeEntry): Boolean =
        entry.type == "blob" && entry.path.endsWith(".md") && !entry.path.endsWith(".reflect.md")

    private fun mimeTypeFor(path: String): String? = when (path.substringAfterLast('.', "").lowercase()) {
        "jpg", "jpeg" -> "image/jpeg"
        "png" -> "image/png"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "heic", "heif" -> "image/heic"
        else -> null
    }

    private fun logSyncFailure(stage: String, error: Exception) {
        val httpError = error as? HttpException
        val status = httpError?.code()?.toString() ?: "unknown"
        val responseBody = httpError?.response()?.errorBody()?.string()
            ?.replace(Regex("\\s+"), " ")
            ?.take(2000)
        logError("Sync failed stage=$stage status=$status response=${responseBody ?: "<none>"}", error)
    }

    private suspend fun <T> runSyncStage(stage: String, operation: suspend () -> T): T {
        logDebug("Sync stage=$stage")
        return try {
            operation()
        } catch (e: Exception) {
            logSyncFailure(stage, e)
            throw e
        }
    }

    private fun userFacingSyncError(operation: String, error: Exception): String {
        return when {
            (error as? HttpException)?.code() == 401 || (error as? HttpException)?.code() == 403 ->
                "Unable to access GitHub during $operation. Check that your PAT has access to this repository."
            error is IOException ->
                "Unable to reach GitHub during $operation. Check your internet connection and try again."
            else ->
                "Sync failed during $operation. Check the GitHub settings and try again."
        }
    }

    private fun userFacingPushError(error: Exception): String {
        return when {
            (error as? HttpException)?.code() == 401 || (error as? HttpException)?.code() == 403 ->
                "Unable to push notes to GitHub. Check that your PAT has Contents: Read and write permission for this repository."
            error is IOException ->
                "Unable to reach GitHub to push notes. Check your internet connection and try again."
            else ->
                "Unable to push notes to GitHub. Check your PAT permissions and try again."
        }
    }

    private fun logDebug(message: String) = runCatching { Log.d(TAG, message) }

    private fun logInfo(message: String) = runCatching { Log.i(TAG, message) }

    private fun logWarn(message: String) = runCatching { Log.w(TAG, message) }

    private fun logError(message: String, error: Throwable) = runCatching { Log.e(TAG, message, error) }

    companion object {
        private const val TAG = "SyncEngine"
    }
}
