package com.specular.android.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface NoteDao {
    @Query("SELECT * FROM notes ORDER BY isDaily DESC, updatedAt DESC")
    fun observeAll(): Flow<List<NoteEntity>>

    @Query("SELECT * FROM notes WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): NoteEntity?

    @Query("SELECT * FROM notes WHERE path = :path LIMIT 1")
    suspend fun getByPath(path: String): NoteEntity?

    @Query("SELECT * FROM notes WHERE isDirty = 1")
    suspend fun getDirty(): List<NoteEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: NoteEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<NoteEntity>)

    @Query("DELETE FROM notes WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("SELECT notes.* FROM notes JOIN notes_fts ON notes.id = notes_fts.docid WHERE notes_fts MATCH :query")
    fun searchFts(query: String): Flow<List<NoteEntity>>

    @Query("SELECT * FROM notes WHERE title LIKE '%' || :q || '%' OR body LIKE '%' || :q || '%' ORDER BY updatedAt DESC")
    fun searchLike(q: String): Flow<List<NoteEntity>>

    @Query("UPDATE notes SET isDirty = :dirty, lastRemoteSha = :sha WHERE id = :id")
    suspend fun markDirty(id: String, dirty: Boolean, sha: String?)
}
