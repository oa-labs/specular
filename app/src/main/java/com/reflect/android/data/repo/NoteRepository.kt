package com.specular.android.data.repo

import android.util.Base64
import com.specular.android.data.local.FileStore
import com.specular.android.data.local.FrontmatterParser
import com.specular.android.data.local.NoteDao
import com.specular.android.data.local.NoteEntity
import com.specular.android.data.local.NoteStoreLock
import com.specular.android.data.remote.GitHubApi
import com.specular.android.data.remote.GitHubAuth
import com.specular.android.data.remote.AiProviderSettings
import com.specular.android.data.remote.AiSnippetGenerator
import com.specular.android.domain.model.Note
import com.specular.android.domain.model.NoteListItem
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NoteRepository @Inject constructor(
    private val dao: NoteDao,
    private val fileStore: FileStore,
    private val githubApi: GitHubApi,
    private val auth: GitHubAuth,
    private val aiSettings: AiProviderSettings,
    private val snippetGenerator: AiSnippetGenerator,
    private val noteStoreLock: NoteStoreLock
) {
    private data class SnippetGenerationInput(
        val entity: NoteEntity,
        val content: String
    )
    fun observeNotes(): Flow<List<NoteListItem>> = dao.observeAll().map { list ->
        list.map { e ->
            NoteListItem(
                id = e.id,
                title = e.title,
                path = e.path,
                snippet = FrontmatterParser.snippetOrEmpty(e.body, e.snippet),
                isDaily = e.isDaily,
                isDirty = e.isDirty,
                isConflict = e.isConflict,
                updatedAt = e.updatedAt
            )
        }
    }

    /**
     * Import all local markdown files into the database.
     * This is the reliable way to populate notes after a pull.
     */
    suspend fun importFromFiles() {
        val files = fileStore.listAllMarkdown()
        val entities = files.map { (path, raw) ->
            val parsed = FrontmatterParser.parse(path, raw)
            val id = FrontmatterParser.identityFor(path, parsed.id)
            val existing = dao.getByPath(path) ?: dao.getById(id)
            existing?.copy(
                title = parsed.title.ifBlank { path.removeSuffix(".md") },
                path = path,
                rawMarkdown = raw,
                body = parsed.body,
                aliases = parsed.aliases.toString(),
                snippet = FrontmatterParser.snippetOrEmpty(parsed.body, parsed.snippet),
                isDaily = path.startsWith("daily/")
            ) ?: NoteEntity(
                id = id,
                title = parsed.title.ifBlank { path.removeSuffix(".md") },
                path = path,
                rawMarkdown = raw,
                body = parsed.body,
                aliases = parsed.aliases.toString(),
                snippet = FrontmatterParser.snippetOrEmpty(parsed.body, parsed.snippet),
                isDaily = path.startsWith("daily/"),
                lastRemoteSha = null,
                isDirty = false,
                isConflict = false
            )
        }
        if (entities.isNotEmpty()) {
            dao.upsertAll(entities)
        }
    }

    suspend fun getNote(id: String): Note? {
        val e = dao.getById(id) ?: return null
        return Note(
            id = e.id,
            title = e.title,
            path = e.path,
            rawMarkdown = e.rawMarkdown,
            bodyMarkdown = e.body,
            snippet = FrontmatterParser.snippetOrEmpty(e.body, e.snippet),
            aliases = e.aliases.removeSurrounding("[", "]").split(",").map { it.trim().removeSurrounding("\"") }.filter { it.isNotEmpty() },
            isDaily = e.isDaily,
            lastRemoteSha = e.lastRemoteSha,
            isDirty = e.isDirty,
            isConflict = e.isConflict
        )
    }

    suspend fun createNote(title: String, body: String = ""): Note {
        val id = "01" + UUID.randomUUID().toString().replace("-", "").take(24)
        val slug = title.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-').ifEmpty { "untitled" }
        val path = "$slug.md"
        val frontmatter = FrontmatterParser.generateFrontmatter(id)
        val raw = frontmatter + "# $title\n\n$body\n"
        fileStore.write(path, raw)
        val entity = NoteEntity(
            id = id,
            title = title,
            path = path,
            rawMarkdown = raw,
            body = "# $title\n\n$body",
            aliases = "[]",
            snippet = null,
            isDaily = false,
            lastRemoteSha = null,
            isDirty = true
        )
        dao.upsert(entity)
        return getNote(id)!!
    }

    suspend fun updateNote(id: String, newTitle: String? = null, newBody: String? = null): Note {
        val e = dao.getById(id) ?: error("Note $id not found")
        val parsed = FrontmatterParser.parse(e.path, e.rawMarkdown)
        val title = newTitle ?: parsed.title
        val body = newBody ?: parsed.body
        // Re-generate file — keep id stable
        val stableId = FrontmatterParser.identityFor(e.path, parsed.id ?: id)
        val frontmatter = parsed.rawFrontmatter?.let {
            "---\n${FrontmatterParser.upsertIdInFrontmatter(it, stableId)}\n---\n"
        } ?: FrontmatterParser.generateFrontmatter(stableId, parsed.aliases, parsed.snippet)
        val raw = frontmatter + body.let { if (it.startsWith("# ")) it else "# $title\n\n$it" }
        // If title changed, keep path stable for now (rename is explicit op)
        fileStore.write(e.path, raw)
        val updated = e.copy(
            title = title,
            rawMarkdown = raw,
            body = body,
            snippet = parsed.snippet,
            isDirty = true,
            updatedAt = System.currentTimeMillis()
        )
        dao.upsert(updated)
        return getNote(id)!!
    }

    suspend fun deleteNote(id: String) {
        val e = dao.getById(id) ?: return
        fileStore.delete(e.path)
        dao.deleteById(id)
        // Sync will handle remote delete on next push
    }

    fun search(query: String): Flow<List<NoteListItem>> {
        return if (query.length >= 2) {
            dao.searchLike(query).map { list ->
                list.map { e ->
                    NoteListItem(
                        id = e.id,
                        title = e.title,
                        path = e.path,
                        snippet = FrontmatterParser.snippetOrEmpty(e.body, e.snippet),
                        isDaily = e.isDaily,
                        isDirty = e.isDirty,
                        isConflict = e.isConflict,
                        updatedAt = e.updatedAt
                    )
                }
            }
        } else {
            observeNotes()
        }
    }

    /** Generates and persists a snippet. Existing snippets are kept unless [force] is true. */
    suspend fun generateSnippet(id: String, force: Boolean = false): Boolean = withContext(Dispatchers.IO) {
        val input = noteStoreLock.withLock {
            val entity = dao.getById(id) ?: return@withLock null
            val parsed = FrontmatterParser.parse(entity.path, entity.rawMarkdown)
            if (!force && !parsed.snippet.isNullOrBlank()) {
                if (entity.snippet != parsed.snippet) dao.upsert(entity.copy(snippet = parsed.snippet))
                return@withLock null
            }
            SnippetGenerationInput(entity, FrontmatterParser.aiSnippetContent(parsed.body))
        } ?: return@withContext false

        val snippet = if (FrontmatterParser.isEmptySnippetContent(input.content)) {
            FrontmatterParser.EMPTY_NOTE_SNIPPET
        } else {
            val config = aiSettings.config.value ?: return@withContext false
            snippetGenerator.generate(config, input.content)
        }

        noteStoreLock.withLock {
            val current = dao.getById(id) ?: return@withLock false
            if (current.path != input.entity.path || current.rawMarkdown != input.entity.rawMarkdown) {
                // Sync or an editor save won the race; never write a snippet to a stale path.
                return@withLock false
            }
            val raw = FrontmatterParser.upsertSnippet(current.path, current.rawMarkdown, snippet)
            fileStore.write(current.path, raw)
            dao.upsert(
                current.copy(
                    rawMarkdown = raw,
                    snippet = snippet,
                    isDirty = true,
                    updatedAt = System.currentTimeMillis()
                )
            )
            true
        }
    }


}
