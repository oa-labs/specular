package com.specular.android.sync

import android.util.Log
import com.specular.android.data.local.FileStore
import com.specular.android.data.local.FrontmatterParser
import com.specular.android.data.local.NoteDao
import com.specular.android.data.local.NoteEntity
import com.specular.android.data.local.NoteStoreLock
import com.specular.android.data.local.TodoIndex
import com.specular.android.data.remote.GitHubApi
import com.specular.android.data.remote.GitHubAuth
import com.specular.android.data.remote.PutContentRequest
import com.specular.android.data.remote.DeleteContentRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Base64
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
    private val todoIndex: TodoIndex = TodoIndex()
) {
    sealed class Result {
        data object Success : Result()
        data class Error(val message: String) : Result()
        data object NotConfigured : Result()
    }

    suspend fun pull(): Result = noteStoreLock.withLock { pullLocked() }

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
            logDebug("Pull tree loaded markdownCandidates=${tree.tree.count { it.type == "blob" && it.path.endsWith(".md") }}")

            for (entry in tree.tree) {
                if (entry.type != "blob" || !entry.path.endsWith(".md")) continue
                val local = dao.getByPath(entry.path)
                // A locally requested deletion is authoritative until its remote
                // operation completes. Do not revive it during the pull phase.
                if (local?.isPendingDeletion == true) continue
                // A matching remote SHA means the remote has not changed. Keep a dirty
                // local copy intact so the subsequent push can publish it.
                if (local?.lastRemoteSha == entry.sha) continue

                val contentResponse = runSyncStage("pull:download path=${entry.path}") {
                    api.getContent(owner, repo, entry.path, header, ref = branch)
                }
                val raw = contentResponse.content?.let { b64 ->
                    String(Base64.getDecoder().decode(b64.replace("\n", "")), Charsets.UTF_8)
                } ?: continue

                // Keep local edits intact and retain the remote copy as a conflict.
                if (local != null && local.isDirty && local.lastRemoteSha != entry.sha) {
                    val conflictPath = entry.path.removeSuffix(".md") +
                        " (conflict ${java.time.LocalDate.now()}).md"
                    runSyncStage("pull:write conflict path=$conflictPath") {
                        fileStore.write(conflictPath, raw)
                        val parsed = FrontmatterParser.parse(entry.path, raw)
                        val entity = NoteEntity(
                                id = "${FrontmatterParser.identityFor(entry.path, parsed.id)}:conflict:${entry.sha}",
                                title = parsed.title + " (conflict)",
                                path = conflictPath,
                                rawMarkdown = raw,
                                body = parsed.body,
                                aliases = parsed.aliases.toString(),
                                snippet = FrontmatterParser.snippetOrEmpty(parsed.body, parsed.snippet),
                                isDaily = conflictPath.startsWith("daily/"),
                                lastRemoteSha = entry.sha,
                                isConflict = true
                            )
                        dao.upsertNoteAndReplaceTodos(entity, todoIndex.extract(entity.id, entity.body))
                    }
                    continue
                }

                runSyncStage("pull:persist path=${entry.path}") {
                    fileStore.write(entry.path, raw)
                    val parsed = FrontmatterParser.parse(entry.path, raw)
                    val entity = NoteEntity(
                            id = FrontmatterParser.identityFor(entry.path, parsed.id),
                            title = parsed.title,
                            path = entry.path,
                            rawMarkdown = raw,
                            body = parsed.body,
                            aliases = parsed.aliases.toString(),
                            snippet = FrontmatterParser.snippetOrEmpty(parsed.body, parsed.snippet),
                            isDaily = entry.path.startsWith("daily/"),
                            lastRemoteSha = entry.sha,
                            isDirty = false,
                            isConflict = false
                        )
                    dao.upsertNoteAndReplaceTodos(entity, todoIndex.extract(entity.id, entity.body))
                }
            }
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
            val dirty = runSyncStage("push:load dirty notes") { dao.getDirty() }
                .filterNot { it.isPendingDeletion }
            if (dirty.isEmpty() && pendingDeletions.isEmpty()) {
                logInfo("Push skipped: no dirty notes")
                return@withContext Result.Success
            }
            logDebug("Push queued notes=${dirty.size} deletions=${pendingDeletions.size}")
            var failedPushes = 0
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
    }

    private fun logPushFailure(path: String, error: Exception) {
        logSyncFailure("push:upload path=$path", error)
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
