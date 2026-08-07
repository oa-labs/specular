package com.specular.android.sync

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
                if (local?.lastRemoteSha == entry.sha && !local.isDirty) continue

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
                            id = "${parsed.id ?: entry.path}:conflict:${entry.sha}",
                            title = parsed.title + " (conflict)",
                            path = conflictPath,
                            rawMarkdown = raw,
                            body = parsed.body,
                            aliases = parsed.aliases.toString(),
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
                        id = parsed.id ?: entry.path,
                        title = parsed.title,
                        path = entry.path,
                        rawMarkdown = raw,
                        body = parsed.body,
                        aliases = parsed.aliases.toString(),
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
                // 409/422 means sha mismatch — leave dirty for next pull to create conflict
                if (ex.message?.contains("409") == true || ex.message?.contains("422") == true) {
                    continue
                }
                return@withContext Result.Error(ex.message ?: ex.toString())
            }
        }
        Result.Success
    }

    suspend fun sync(): Result {
        val pullResult = pull()
        if (pullResult is Result.Error) return pullResult
        if (pullResult is Result.NotConfigured) return pullResult
        return push()
    }
}
