package com.specular.android.sync

import com.specular.android.data.local.FileStore
import com.specular.android.data.local.NoteDao
import com.specular.android.data.local.NoteEntity
import com.specular.android.data.local.TodoEntity
import com.specular.android.data.local.TodoIndexState
import com.specular.android.data.remote.ContentResponse
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
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
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
            override suspend fun getDirty(): List<NoteEntity> = listOf(local)
            override suspend fun getPendingDeletions(): List<NoteEntity> = emptyList()
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
            override suspend fun getDirty(): List<NoteEntity> = emptyList()
            override suspend fun getPendingDeletions(): List<NoteEntity> = emptyList()
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
            override suspend fun getDirty(): List<NoteEntity> = emptyList()
            override suspend fun getPendingDeletions(): List<NoteEntity> = listOf(pending)
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
}
