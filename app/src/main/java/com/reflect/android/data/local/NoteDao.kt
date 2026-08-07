package com.specular.android.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.paging.PagingSource
import com.specular.android.domain.model.TodoListItem
import kotlinx.coroutines.flow.Flow

@Dao
interface NoteDao {
    @Query("SELECT * FROM notes WHERE isPendingDeletion = 0 ORDER BY isDaily DESC, updatedAt DESC")
    fun observeAll(): Flow<List<NoteEntity>>

    @Query("SELECT * FROM notes WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): NoteEntity?

    @Query("SELECT * FROM notes WHERE path = :path LIMIT 1")
    suspend fun getByPath(path: String): NoteEntity?

    @Query("SELECT * FROM notes WHERE isDirty = 1")
    suspend fun getDirty(): List<NoteEntity>

    @Query("SELECT * FROM notes WHERE isPendingDeletion = 1")
    suspend fun getPendingDeletions(): List<NoteEntity>

    @Query("SELECT * FROM notes")
    suspend fun getAllForTodoIndex(): List<NoteEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: NoteEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<NoteEntity>)

    @Query("DELETE FROM notes WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM todo_index WHERE noteId = :noteId")
    suspend fun deleteTodosForNote(noteId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertTodos(todos: List<TodoEntity>)

    @Transaction
    suspend fun upsertNoteAndReplaceTodos(note: NoteEntity, todos: List<TodoEntity>) {
        upsert(note)
        deleteTodosForNote(note.id)
        if (todos.isNotEmpty()) upsertTodos(todos)
    }

    @Transaction
    suspend fun deleteNoteAndTodos(noteId: String) {
        deleteTodosForNote(noteId)
        deleteById(noteId)
    }

    @Query("SELECT isReady FROM todo_index_state WHERE id = 0 LIMIT 1")
    suspend fun todoIndexReady(): Boolean?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun setTodoIndexState(state: TodoIndexState)

    @Query("DELETE FROM todo_index")
    suspend fun clearTodos()

    @Transaction
    suspend fun replaceAllTodos(todos: List<TodoEntity>) {
        clearTodos()
        if (todos.isNotEmpty()) upsertTodos(todos)
        setTodoIndexState(TodoIndexState(isReady = true))
    }

    @Query(
        "SELECT t.noteId, t.taskIndex, t.text, t.isCompleted, n.title AS noteTitle " +
            "FROM todo_index t JOIN notes n ON n.id = t.noteId " +
            "WHERE n.isPendingDeletion = 0 AND t.isCompleted = :completed " +
            "ORDER BY n.updatedAt DESC, t.taskIndex ASC"
    )
    fun observeTodosByCompletion(completed: Boolean): PagingSource<Int, TodoListItem>

    @Query(
        "SELECT t.noteId, t.taskIndex, t.text, t.isCompleted, n.title AS noteTitle " +
            "FROM todo_index t JOIN notes n ON n.id = t.noteId " +
            "WHERE n.isPendingDeletion = 0 " +
            "ORDER BY n.updatedAt DESC, t.taskIndex ASC"
    )
    fun observeAllTodos(): PagingSource<Int, TodoListItem>

    @Query("SELECT notes.* FROM notes JOIN notes_fts ON notes.id = notes_fts.docid WHERE notes_fts MATCH :query")
    fun searchFts(query: String): Flow<List<NoteEntity>>

    @Query("SELECT * FROM notes WHERE title LIKE '%' || :q || '%' OR body LIKE '%' || :q || '%' ORDER BY updatedAt DESC")
    fun searchLike(q: String): Flow<List<NoteEntity>>

    @Query("UPDATE notes SET isDirty = :dirty, lastRemoteSha = :sha WHERE id = :id")
    suspend fun markDirty(id: String, dirty: Boolean, sha: String?)
}
