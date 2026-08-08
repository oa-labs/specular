package com.specular.android.sync

import com.specular.android.data.local.FileStore
import com.specular.android.data.local.AttachmentDao
import com.specular.android.data.local.AttachmentEntity
import com.specular.android.data.local.NoteDao
import com.specular.android.data.local.NoteEntity
import com.specular.android.data.local.NoteStoreLock
import com.specular.android.data.local.TodoEntity
import com.specular.android.data.local.TodoIndexState
import com.specular.android.data.local.TodoIndex
import com.specular.android.data.repo.NoteRepository
import com.specular.android.data.remote.AiProviderSettings
import com.specular.android.data.remote.AiSnippetGenerator
import com.specular.android.data.remote.ContentResponse
import com.specular.android.data.remote.BlobResponse
import com.specular.android.data.remote.DeleteContentRequest
import com.specular.android.data.remote.GitHubApi
import com.specular.android.data.remote.GitHubAuth
import com.specular.android.data.remote.RefObject
import com.specular.android.data.remote.RefResponse
import com.specular.android.data.remote.RepoResponse
import com.specular.android.data.remote.TreeEntry
import com.specular.android.data.remote.TreeResponse
import com.specular.android.data.remote.Owner
import com.specular.android.data.remote.PutContentResponse
import com.specular.android.data.remote.PutContentRequest
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flowOf
import androidx.paging.PagingSource
import com.specular.android.domain.model.TodoListItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions
import org.mockito.Mockito.`when`
import java.util.Base64

class SyncEngineTest {
    @Test
    fun pullDoesNotOverwriteDirtyNoteWhenRemoteShaIsUnchanged() = runTest {
        val api = mock(GitHubApi::class.java)
        val auth = mock(GitHubAuth::class.java)
        val fileStore = mock(FileStore::class.java)
        val upserted = mutableListOf<NoteEntity>()
        val local = NoteEntity(
            id = "01local-note",
            title = "Local note",
            path = "local.md",
            rawMarkdown = "# Local edit",
            body = "# Local edit",
            aliases = "[]",
            isDaily = false,
            lastRemoteSha = "same-sha",
            isDirty = true
        )
        val dao = object : NoteDao {
            override fun observeAll(): Flow<List<NoteEntity>> = emptyFlow()
            override suspend fun getById(id: String): NoteEntity? = null
            override suspend fun getByPath(path: String): NoteEntity? = local
            override suspend fun getByPathIgnoringCase(path: String): NoteEntity? = local
            override suspend fun getDirty(): List<NoteEntity> = listOf(local)
            override suspend fun getPendingDeletions(): List<NoteEntity> = emptyList()
            override suspend fun getPendingRenames(): List<NoteEntity> = emptyList()
            override suspend fun getAllForTodoIndex(): List<NoteEntity> = emptyList()
            override suspend fun upsert(entity: NoteEntity) { upserted += entity }
            override suspend fun upsertAll(entities: List<NoteEntity>) { upserted += entities }
            override suspend fun deleteById(id: String) = Unit
            override suspend fun deleteTodosForNote(noteId: String) = Unit
            override suspend fun upsertTodos(todos: List<TodoEntity>) = Unit
            override suspend fun todoIndexReady(): Boolean? = true
            override suspend fun setTodoIndexState(state: TodoIndexState) = Unit
            override suspend fun clearTodos() = Unit
            override fun observeTodosByCompletion(completed: Boolean): PagingSource<Int, TodoListItem> = error("unused")
            override fun observeAllTodos(): PagingSource<Int, TodoListItem> = error("unused")
            override fun searchFts(query: String): Flow<List<NoteEntity>> = emptyFlow()
            override fun searchLike(q: String): Flow<List<NoteEntity>> = emptyFlow()
            override suspend fun markDirty(id: String, dirty: Boolean, sha: String?) = Unit
        }

        `when`(auth.authHeader()).thenReturn("Bearer token")
        `when`(auth.repoOwner).thenReturn("owner")
        `when`(auth.repoName).thenReturn("repo")
        `when`(api.getRepo("owner", "repo", "Bearer token"))
            .thenReturn(RepoResponse(1L, "repo", "owner/repo", false, "main", Owner("owner")))
        `when`(api.getRef("owner", "repo", "main", "Bearer token"))
            .thenReturn(RefResponse("refs/heads/main", RefObject("commit-sha", "commit")))
        `when`(api.getTree("owner", "repo", "commit-sha", "Bearer token", 1))
            .thenReturn(
                TreeResponse(
                    sha = "tree-sha",
                    tree = listOf(TreeEntry("local.md", "100644", "blob", "same-sha")),
                    truncated = false
                )
            )

        val result = SyncEngine(api, auth, dao, fileStore).pull()

        assertTrue(result is SyncEngine.Result.Success)
        assertTrue(upserted.isEmpty())
        verify(api, never()).getContent("owner", "repo", "local.md", "Bearer token", "main")
        verifyNoInteractions(fileStore)
    }

    @Test
    fun pullIndexesRemoteMarkdownInRoom() = runTest {
        val api = mock(GitHubApi::class.java)
        val auth = mock(GitHubAuth::class.java)
        val upserted = mutableListOf<NoteEntity>()
        val dao = object : NoteDao {
            override fun observeAll(): Flow<List<NoteEntity>> = emptyFlow()
            override suspend fun getById(id: String): NoteEntity? = null
            override suspend fun getByPath(path: String): NoteEntity? = null
            override suspend fun getByPathIgnoringCase(path: String): NoteEntity? = null
            override suspend fun getDirty(): List<NoteEntity> = emptyList()
            override suspend fun getPendingDeletions(): List<NoteEntity> = emptyList()
            override suspend fun getPendingRenames(): List<NoteEntity> = emptyList()
            override suspend fun getAllForTodoIndex(): List<NoteEntity> = emptyList()
            override suspend fun upsert(entity: NoteEntity) { upserted += entity }
            override suspend fun upsertAll(entities: List<NoteEntity>) { upserted += entities }
            override suspend fun deleteById(id: String) = Unit
            override suspend fun deleteTodosForNote(noteId: String) = Unit
            override suspend fun upsertTodos(todos: List<TodoEntity>) = Unit
            override suspend fun todoIndexReady(): Boolean? = true
            override suspend fun setTodoIndexState(state: TodoIndexState) = Unit
            override suspend fun clearTodos() = Unit
            override fun observeTodosByCompletion(completed: Boolean): PagingSource<Int, TodoListItem> = error("unused")
            override fun observeAllTodos(): PagingSource<Int, TodoListItem> = error("unused")
            override fun searchFts(query: String): Flow<List<NoteEntity>> = emptyFlow()
            override fun searchLike(q: String): Flow<List<NoteEntity>> = emptyFlow()
            override suspend fun markDirty(id: String, dirty: Boolean, sha: String?) = Unit
        }
        val fileStore = mock(FileStore::class.java)
        val raw = """
            ---
            id: 01remote-note
            ---
            # Remote note

            Content from GitHub.
        """.trimIndent()

        `when`(auth.authHeader()).thenReturn("Bearer token")
        `when`(auth.repoOwner).thenReturn("owner")
        `when`(auth.repoName).thenReturn("repo")
        `when`(api.getRepo("owner", "repo", "Bearer token"))
            .thenReturn(RepoResponse(1L, "repo", "owner/repo", false, "main", Owner("owner")))
        `when`(api.getRef("owner", "repo", "main", "Bearer token"))
            .thenReturn(RefResponse("refs/heads/main", RefObject("commit-sha", "commit")))
        `when`(api.getTree("owner", "repo", "commit-sha", "Bearer token", 1))
            .thenReturn(
                TreeResponse(
                    sha = "tree-sha",
                    tree = listOf(TreeEntry("remote.md", "100644", "blob", "blob-sha")),
                    truncated = false
                )
            )
        `when`(api.getContent("owner", "repo", "remote.md", "Bearer token", "main"))
            .thenReturn(
                ContentResponse(
                    name = "remote.md",
                    path = "remote.md",
                    sha = "blob-sha",
                    content = Base64.getEncoder().encodeToString(raw.toByteArray()),
                    encoding = "base64",
                    type = "file"
                )
            )

        val result = SyncEngine(api, auth, dao, fileStore).pull()

        assertTrue(result is SyncEngine.Result.Success)
        verify(fileStore).write("remote.md", raw)
        assertEquals(1, upserted.size)
        assertEquals("01remote-note", upserted.single().id)
        assertEquals("Remote note", upserted.single().title)
        assertEquals("blob-sha", upserted.single().lastRemoteSha)
    }

    @Test
    fun pushDeletesPendingNoteFromGitHubAndThenLocally() = runTest {
        val api = mock(GitHubApi::class.java)
        val auth = mock(GitHubAuth::class.java)
        val fileStore = mock(FileStore::class.java)
        val deletedIds = mutableListOf<String>()
        val pending = NoteEntity(
            id = "01deleted-note",
            title = "Deleted note",
            path = "deleted.md",
            rawMarkdown = "# Deleted note",
            body = "# Deleted note",
            aliases = "[]",
            isDaily = false,
            lastRemoteSha = "remote-sha",
            isPendingDeletion = true
        )
        val dao = object : NoteDao {
            override fun observeAll(): Flow<List<NoteEntity>> = emptyFlow()
            override suspend fun getById(id: String): NoteEntity? = pending
            override suspend fun getByPath(path: String): NoteEntity? = pending
            override suspend fun getByPathIgnoringCase(path: String): NoteEntity? = pending
            override suspend fun getDirty(): List<NoteEntity> = emptyList()
            override suspend fun getPendingDeletions(): List<NoteEntity> = listOf(pending)
            override suspend fun getPendingRenames(): List<NoteEntity> = emptyList()
            override suspend fun getAllForTodoIndex(): List<NoteEntity> = emptyList()
            override suspend fun upsert(entity: NoteEntity) = Unit
            override suspend fun upsertAll(entities: List<NoteEntity>) = Unit
            override suspend fun deleteById(id: String) { deletedIds += id }
            override suspend fun deleteTodosForNote(noteId: String) = Unit
            override suspend fun upsertTodos(todos: List<TodoEntity>) = Unit
            override suspend fun todoIndexReady(): Boolean? = true
            override suspend fun setTodoIndexState(state: TodoIndexState) = Unit
            override suspend fun clearTodos() = Unit
            override fun observeTodosByCompletion(completed: Boolean): PagingSource<Int, TodoListItem> = error("unused")
            override fun observeAllTodos(): PagingSource<Int, TodoListItem> = error("unused")
            override fun searchFts(query: String): Flow<List<NoteEntity>> = emptyFlow()
            override fun searchLike(q: String): Flow<List<NoteEntity>> = emptyFlow()
            override suspend fun markDirty(id: String, dirty: Boolean, sha: String?) = Unit
        }

        `when`(auth.authHeader()).thenReturn("Bearer token")
        `when`(auth.repoOwner).thenReturn("owner")
        `when`(auth.repoName).thenReturn("repo")
        `when`(api.getRepo("owner", "repo", "Bearer token"))
            .thenReturn(RepoResponse(1L, "repo", "owner/repo", false, "main", Owner("owner")))
        `when`(
            api.deleteContent(
                "owner", "repo", "deleted.md", "Bearer token",
                DeleteContentRequest("Delete Deleted note", "remote-sha", "main")
            )
        ).thenReturn(PutContentResponse(content = null, commit = null))

        val result = SyncEngine(api, auth, dao, fileStore).push()

        assertTrue(result is SyncEngine.Result.Success)
        verify(api).deleteContent(
            "owner", "repo", "deleted.md", "Bearer token",
            DeleteContentRequest("Delete Deleted note", "remote-sha", "main")
        )
        verify(fileStore).delete("deleted.md")
        assertEquals(listOf("01deleted-note"), deletedIds)
    }

    @Test
    fun pullRemovesCleanLocalNoteDeletedRemotely() = runTest {
        val api = mock(GitHubApi::class.java)
        val auth = mock(GitHubAuth::class.java)
        val fileStore = mock(FileStore::class.java)
        val local = testNote(id = "01deleted", path = "gone.md", sha = "old-sha")
        val dao = MemoryNoteDao(local)
        configurePull(api, auth, emptyList())

        val result = SyncEngine(api, auth, dao, fileStore).pull()

        assertTrue(result is SyncEngine.Result.Success)
        assertTrue(dao.entities().isEmpty())
        verify(fileStore).delete("gone.md")
    }

    @Test
    fun pullPreservesDirtyLocalNoteAsConflictWhenDeletedRemotely() = runTest {
        val api = mock(GitHubApi::class.java)
        val auth = mock(GitHubAuth::class.java)
        val fileStore = mock(FileStore::class.java)
        val local = testNote(
            id = "01dirty", path = "gone.md", sha = "old-sha", dirty = true,
            raw = "---\nid: 01dirty\n---\n# Local edit\n\nKeep this"
        )
        val dao = MemoryNoteDao(local)
        `when`(fileStore.read("gone.md")).thenReturn(local.rawMarkdown)
        configurePull(api, auth, emptyList())

        val result = SyncEngine(api, auth, dao, fileStore).pull()

        assertTrue(result is SyncEngine.Result.Success)
        val conflict = dao.entities().single()
        assertTrue(conflict.isConflict)
        assertTrue(conflict.isDirty)
        assertTrue(conflict.path.startsWith("gone (conflict "))
        assertTrue(conflict.rawMarkdown.contains("# Local edit"))
        verify(fileStore).delete("gone.md")
    }

    @Test
    fun pullReconcilesCleanRemoteRenameByStableId() = runTest {
        val api = mock(GitHubApi::class.java)
        val auth = mock(GitHubAuth::class.java)
        val fileStore = mock(FileStore::class.java)
        val local = testNote(id = "01same", path = "old-name.md", sha = "old-sha")
        val dao = MemoryNoteDao(local)
        val remoteRaw = "---\nid: 01same\n---\n# Renamed\n\nRemote content"
        configurePull(api, auth, listOf(TreeEntry("renamed.md", "100644", "blob", "new-sha")))
        `when`(api.getContent("owner", "repo", "renamed.md", "Bearer token", "main"))
            .thenReturn(content("renamed.md", "new-sha", remoteRaw))

        val result = SyncEngine(api, auth, dao, fileStore).pull()

        assertTrue(result is SyncEngine.Result.Success)
        val note = dao.entities().single()
        assertEquals("01same", note.id)
        assertEquals("renamed.md", note.path)
        assertEquals("new-sha", note.lastRemoteSha)
        verify(fileStore).delete("old-name.md")
        verify(fileStore).write("renamed.md", remoteRaw)
    }

    @Test
    fun pullPreservesConcurrentLocalEditWhenRemoteRenamesSameId() = runTest {
        val api = mock(GitHubApi::class.java)
        val auth = mock(GitHubAuth::class.java)
        val fileStore = mock(FileStore::class.java)
        val local = testNote(
            id = "01same", path = "old-name.md", sha = "old-sha", dirty = true,
            raw = "---\nid: 01same\n---\n# Local edit\n\nLocal content"
        )
        val dao = MemoryNoteDao(local)
        `when`(fileStore.read("old-name.md")).thenReturn(local.rawMarkdown)
        val remoteRaw = "---\nid: 01same\n---\n# Renamed remotely\n\nRemote content"
        configurePull(api, auth, listOf(TreeEntry("renamed.md", "100644", "blob", "new-sha")))
        `when`(api.getContent("owner", "repo", "renamed.md", "Bearer token", "main"))
            .thenReturn(content("renamed.md", "new-sha", remoteRaw))

        val result = SyncEngine(api, auth, dao, fileStore).pull()

        assertTrue(result is SyncEngine.Result.Success)
        val remote = dao.entities().single { it.id == "01same" }
        val conflict = dao.entities().single { it.isConflict }
        assertEquals("renamed.md", remote.path)
        assertTrue(!remote.isDirty)
        assertTrue(conflict.isDirty)
        assertTrue(conflict.path.startsWith("old-name (conflict "))
        assertTrue(conflict.rawMarkdown.contains("Local content"))
    }

    @Test
    fun pullTurnsConcurrentSamePathEditIntoPushableConflict() = runTest {
        val api = mock(GitHubApi::class.java)
        val auth = mock(GitHubAuth::class.java)
        val fileStore = mock(FileStore::class.java)
        val local = testNote(
            id = "01same", path = "same.md", sha = "old-sha", dirty = true,
            raw = "---\nid: 01same\n---\n# Local\n\nLocal content"
        )
        val dao = MemoryNoteDao(local)
        `when`(fileStore.read("same.md")).thenReturn(local.rawMarkdown)
        val remoteRaw = "---\nid: 01same\n---\n# Remote\n\nRemote content"
        configurePull(api, auth, listOf(TreeEntry("same.md", "100644", "blob", "new-sha")))
        `when`(api.getContent("owner", "repo", "same.md", "Bearer token", "main"))
            .thenReturn(content("same.md", "new-sha", remoteRaw))

        val result = SyncEngine(api, auth, dao, fileStore).pull()

        assertTrue(result is SyncEngine.Result.Success)
        assertEquals("new-sha", dao.entities().single { it.id == "01same" }.lastRemoteSha)
        val conflict = dao.entities().single { it.isConflict }
        assertTrue(conflict.isDirty)
        assertTrue(conflict.rawMarkdown.contains("Local content"))
    }

    @Test
    fun userRenameCreatesDestinationThenQueuesOldRemotePathForDeletion() = runTest {
        val original = testNote(id = "01rename", path = "old.md", sha = "old-sha")
        val dao = MemoryNoteDao(original)
        val fileStore = mock(FileStore::class.java)
        `when`(fileStore.read("old.md")).thenReturn(original.rawMarkdown)
        `when`(fileStore.move("old.md", "new.md")).thenReturn(true)
        val repository = NoteRepository(
            dao,
            fileStore,
            mock(GitHubApi::class.java),
            mock(GitHubAuth::class.java),
            mock(AiProviderSettings::class.java),
            mock(AiSnippetGenerator::class.java),
            NoteStoreLock(),
            TodoIndex()
        )

        val renamed = repository.renameNote("01rename", "new.md")

        assertEquals("new.md", renamed.path)
        val queued = dao.entities().single()
        assertTrue(queued.isDirty)
        assertEquals(null, queued.lastRemoteSha)
        assertEquals("old.md", queued.pendingRenameFromPath)
        assertEquals("old-sha", queued.pendingRenameFromSha)
        verify(fileStore).move("old.md", "new.md")
    }

    @Test
    fun pullDownloadsReferencedAttachmentFromAssetsOrAttachmentsTree() = runTest {
        val api = mock(GitHubApi::class.java)
        val auth = mock(GitHubAuth::class.java)
        val fileStore = mock(FileStore::class.java)
        val dao = MemoryNoteDao()
        val attachments = MemoryAttachmentDao()
        val noteRaw = "---\nid: 01image\n---\n# Image\n\n![](../attachments/photo.png)"
        val imageBytes = byteArrayOf(1, 2, 3, 4)
        configurePull(
            api,
            auth,
            listOf(
                TreeEntry("notes/Image.md", "100644", "blob", "note-sha"),
                TreeEntry("attachments/photo.png", "100644", "blob", "image-sha")
            )
        )
        `when`(api.getContent("owner", "repo", "notes/Image.md", "Bearer token", "main"))
            .thenReturn(content("notes/Image.md", "note-sha", noteRaw))
        `when`(api.getBlob("owner", "repo", "image-sha", "Bearer token"))
            .thenReturn(
                BlobResponse(
                    sha = "image-sha",
                    content = Base64.getEncoder().encodeToString(imageBytes),
                    encoding = "base64",
                    size = imageBytes.size
                )
            )

        val result = SyncEngine(api, auth, dao, fileStore, attachmentDao = attachments).pull()

        assertTrue(result is SyncEngine.Result.Success)
        assertEquals("image-sha", attachments.getByPath("attachments/photo.png")?.lastRemoteSha)
    }

    @Test
    fun pushUploadsDirtyReferencedAttachmentBeforeMarkdown() = runTest {
        val api = mock(GitHubApi::class.java)
        val auth = mock(GitHubAuth::class.java)
        val fileStore = mock(FileStore::class.java)
        val note = testNote(
            id = "01image", path = "notes/Image.md", sha = "note-sha",
            raw = "# Image\n\n![](../attachments/photo.png)"
        )
        val dao = MemoryNoteDao(note)
        val attachment = AttachmentEntity("attachments/photo.png", "image/png", null, isDirty = true)
        val attachments = MemoryAttachmentDao(attachment)
        val bytes = byteArrayOf(9, 8, 7)
        `when`(fileStore.readBytes("attachments/photo.png")).thenReturn(bytes)
        configurePull(api, auth, emptyList())
        val request = PutContentRequest(
            message = "Upload attachment photo.png",
            content = Base64.getEncoder().encodeToString(bytes),
            sha = null,
            branch = "main"
        )
        `when`(api.putContent("owner", "repo", "attachments/photo.png", "Bearer token", request))
            .thenReturn(
                PutContentResponse(
                    content = ContentResponse("photo.png", "attachments/photo.png", "new-sha", null, null, "file"),
                    commit = null
                )
            )

        val result = SyncEngine(api, auth, dao, fileStore, attachmentDao = attachments).push()

        assertTrue(result is SyncEngine.Result.Success)
        assertEquals("new-sha", attachments.getByPath("attachments/photo.png")?.lastRemoteSha)
        assertTrue(attachments.getDirty().isEmpty())
    }

    private suspend fun configurePull(api: GitHubApi, auth: GitHubAuth, entries: List<TreeEntry>) {
        `when`(auth.authHeader()).thenReturn("Bearer token")
        `when`(auth.repoOwner).thenReturn("owner")
        `when`(auth.repoName).thenReturn("repo")
        `when`(api.getRepo("owner", "repo", "Bearer token"))
            .thenReturn(RepoResponse(1L, "repo", "owner/repo", false, "main", Owner("owner")))
        `when`(api.getRef("owner", "repo", "main", "Bearer token"))
            .thenReturn(RefResponse("refs/heads/main", RefObject("commit-sha", "commit")))
        `when`(api.getTree("owner", "repo", "commit-sha", "Bearer token", 1))
            .thenReturn(TreeResponse("tree-sha", entries, false))
    }

    private fun content(path: String, sha: String, raw: String) = ContentResponse(
        name = path,
        path = path,
        sha = sha,
        content = Base64.getEncoder().encodeToString(raw.toByteArray()),
        encoding = "base64",
        type = "file"
    )

    private fun testNote(
        id: String,
        path: String,
        sha: String?,
        dirty: Boolean = false,
        raw: String = "# Note"
    ) = NoteEntity(
        id = id,
        title = "Note",
        path = path,
        rawMarkdown = raw,
        body = raw,
        aliases = "[]",
        isDaily = false,
        lastRemoteSha = sha,
        isDirty = dirty
    )

    private class MemoryNoteDao(vararg initial: NoteEntity) : NoteDao {
        private val notes = initial.associateByTo(linkedMapOf()) { it.id }

        fun entities(): List<NoteEntity> = notes.values.toList()

        override fun observeAll(): Flow<List<NoteEntity>> = emptyFlow()
        override suspend fun getById(id: String): NoteEntity? = notes[id]
        override suspend fun getByPath(path: String): NoteEntity? = notes.values.firstOrNull { it.path == path }
        override suspend fun getByPathIgnoringCase(path: String): NoteEntity? =
            notes.values.firstOrNull { it.path.equals(path, ignoreCase = true) }
        override suspend fun getDirty(): List<NoteEntity> = notes.values.filter { it.isDirty }
        override suspend fun getPendingDeletions(): List<NoteEntity> = notes.values.filter { it.isPendingDeletion }
        override suspend fun getPendingRenames(): List<NoteEntity> =
            notes.values.filter { it.pendingRenameFromPath != null }
        override suspend fun getAllForTodoIndex(): List<NoteEntity> = notes.values.toList()
        override suspend fun upsert(entity: NoteEntity) { notes[entity.id] = entity }
        override suspend fun upsertAll(entities: List<NoteEntity>) {
            for (entity in entities) upsert(entity)
        }
        override suspend fun deleteById(id: String) { notes.remove(id) }
        override suspend fun deleteTodosForNote(noteId: String) = Unit
        override suspend fun upsertTodos(todos: List<TodoEntity>) = Unit
        override suspend fun todoIndexReady(): Boolean? = true
        override suspend fun setTodoIndexState(state: TodoIndexState) = Unit
        override suspend fun clearTodos() = Unit
        override fun observeTodosByCompletion(completed: Boolean): PagingSource<Int, TodoListItem> = error("unused")
        override fun observeAllTodos(): PagingSource<Int, TodoListItem> = error("unused")
        override fun searchFts(query: String): Flow<List<NoteEntity>> = emptyFlow()
        override fun searchLike(q: String): Flow<List<NoteEntity>> = emptyFlow()
        override suspend fun markDirty(id: String, dirty: Boolean, sha: String?) = Unit
    }

    private class MemoryAttachmentDao(vararg initial: AttachmentEntity) : AttachmentDao {
        private val attachments = initial.associateByTo(linkedMapOf()) { it.path }

        override fun observeChangeToken(): Flow<Long?> = flowOf(null)
        override suspend fun getByPath(path: String): AttachmentEntity? = attachments[path]
        override suspend fun getDirty(): List<AttachmentEntity> = attachments.values.filter { it.isDirty }
        override suspend fun upsert(attachment: AttachmentEntity) {
            attachments[attachment.path] = attachment
        }
        override suspend fun deleteByPath(path: String) {
            attachments.remove(path)
        }
    }
}
