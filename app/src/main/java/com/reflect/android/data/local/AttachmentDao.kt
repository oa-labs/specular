package com.specular.android.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface AttachmentDao {
    /** Changes whenever a synced or imported attachment is persisted. */
    @Query("SELECT MAX(updatedAt) FROM attachments")
    fun observeChangeToken(): Flow<Long?>

    @Query("SELECT * FROM attachments WHERE path = :path LIMIT 1")
    suspend fun getByPath(path: String): AttachmentEntity?

    @Query("SELECT * FROM attachments WHERE isDirty = 1")
    suspend fun getDirty(): List<AttachmentEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(attachment: AttachmentEntity)

    @Query("DELETE FROM attachments WHERE path = :path")
    suspend fun deleteByPath(path: String)
}
