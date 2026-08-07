package com.specular.android.sync

import android.util.Log
import com.specular.android.data.local.FileStore
import com.specular.android.data.local.FrontmatterParser
import com.specular.android.data.local.NoteDao
import com.specular.android.data.local.NoteEntity
import com.specular.android.data.remote.GitHubApi
import com.specular.android.data.remote.GitHubAuth
import com.specular.android.data.remote.PutContentRequest
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
    private val fileStore: FileStore
) {
    sealed class Result {
        data object Success : Result()
        data class Error(val message: String) : Result()
        data object NotConfigured : Result()
    }

    suspend fun pull(): Result = withContext(Dispatchers.IO) {
        val header = auth.authHeader() ?: return@withContext Result.NotConfigured
        val owner = auth.repoOwner ?: return@withContext Result.NotConfigured
        val repo = auth.repoName ?: return@withContext Result.NotConfigured

        try {
            val branch = api.getRepo(owner, repo, header).default_branch
            val ref = api.getRef(owner, repo, branch, header)
            val tree = api.getTree(owner, repo, ref.`object`.sha, header, recursive = 1)

            for (entry in tree.tree) {
                if (entry.type != "blob" || !entry.path.endsWith(".md")) continue
                val local = dao.getByPath(entry.path)
                // A matching remote SHA means the remote has not changed. Keep a dirty
                // local copy intact so the subsequent push can publish it.
                if (local?.lastRemoteSha == entry.sha) continue

                val contentResponse = api.getContent(owner, repo, entry.path, header, ref = branch)
                val raw = contentResponse.content?.let { b64 ->
                    String(Base64.getDecoder().decode(b64.replace("\n", "")), Charsets.UTF_8)
                } ?: continue

                // Keep local edits intact and retain the remote copy as a conflict.
                if (local != null && local.isDirty && local.lastRemoteSha != entry.sha) {
                    val conflictPath = entry.path.removeSuffix(".md") +
                        " (conflict ${java.time.LocalDate.now()}).md"
                    fileStore.write(conflictPath, raw)
                    val parsed = FrontmatterParser.parse(entry.path, raw)
                    dao.upsert(
                        NoteEntity(
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
                    )
                    continue
                }

                fileStore.write(entry.path, raw)
                val parsed = FrontmatterParser.parse(entry.path, raw)
                dao.upsert(
                    NoteEntity(
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
                )
            }
            Result.Success
        } catch (e: Exception) {
            Result.Error("Pull failed: ${e.message ?: e.toString()}")
        }
    }

    suspend fun push(): Result = withContext(Dispatchers.IO) {
        val header = auth.authHeader() ?: return@withContext Result.NotConfigured
        val owner = auth.repoOwner ?: return@withContext Result.NotConfigured
        val repo = auth.repoName ?: return@withContext Result.NotConfigured
        val branch = api.getRepo(owner, repo, header).default_branch
        val dirty = dao.getDirty()
        if (dirty.isEmpty()) return@withContext Result.Success
        var failedPushes = 0
        for (e in dirty) {
            val raw = fileStore.read(e.path) ?: e.rawMarkdown
            val b64 = Base64.getEncoder().encodeToString(raw.toByteArray(Charsets.UTF_8))
            try {
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
                fileStore.write(e.path, raw)
                dao.upsert(e.copy(lastRemoteSha = newSha, isDirty = false, isConflict = false))
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
        Result.Success
    }

    suspend fun sync(): Result {
        val pullResult = pull()
        if (pullResult is Result.Error) return pullResult
        if (pullResult is Result.NotConfigured) return pullResult
        return push()
    }

    private fun logPushFailure(path: String, error: Exception) {
        val httpError = error as? HttpException
        val status = httpError?.code()?.toString() ?: "unknown"
        val responseBody = httpError?.response()?.errorBody()?.string()
            ?.replace(Regex("\\s+"), " ")
            ?.take(2000)
        Log.e(
            TAG,
            "GitHub PUT failed path=$path status=$status response=${responseBody ?: "<none>"}",
            error
        )
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

    companion object {
        private const val TAG = "SyncEngine"
    }
}
