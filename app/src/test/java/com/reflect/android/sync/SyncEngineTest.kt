package com.specular.android.sync

import com.specular.android.data.local.FileStore
import com.specular.android.data.local.NoteDao
import com.specular.android.data.local.NoteEntity
import com.specular.android.data.remote.ContentResponse
import com.specular.android.data.remote.GitHubApi
import com.specular.android.data.remote.GitHubAuth
import com.specular.android.data.remote.RefObject
import com.specular.android.data.remote.RefResponse
import com.specular.android.data.remote.RepoResponse
import com.specular.android.data.remote.TreeEntry
import com.specular.android.data.remote.TreeResponse
import com.specular.android.data.remote.Owner
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import java.util.Base64

class SyncEngineTest {
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
            override suspend fun upsert(entity: NoteEntity) { upserted += entity }
            override suspend fun upsertAll(entities: List<NoteEntity>) { upserted += entities }
            override suspend fun deleteById(id: String) = Unit
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
}
