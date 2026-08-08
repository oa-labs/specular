package com.specular.android.data.local

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Fts4
import androidx.room.PrimaryKey

@Entity(tableName = "notes")
data class NoteEntity(
    @PrimaryKey val id: String,
    val title: String,
    val path: String,
    val rawMarkdown: String,
    val body: String,
    val aliases: String, // JSON array string
    val snippet: String? = null,
    val isDaily: Boolean,
    /** Device-local preference; intentionally not written to the Markdown file. */
    val isPinned: Boolean = false,
    val lastRemoteSha: String?,
    val isDirty: Boolean = false,
    /** Hidden locally while its GitHub Contents API deletion is waiting to sync. */
    val isPendingDeletion: Boolean = false,
    /**
     * The old remote path still to remove after this note has been uploaded to
     * [path].  A GitHub Contents API rename is a create followed by a delete,
     * so keeping this on the note makes that two-step operation crash-safe.
     */
    val pendingRenameFromPath: String? = null,
    val pendingRenameFromSha: String? = null,
    val isConflict: Boolean = false,
    val updatedAt: Long = System.currentTimeMillis()
)

// FTS for offline search — mirrors entity but indexed
@Fts4(contentEntity = NoteEntity::class)
@Entity(tableName = "notes_fts")
data class NoteFts(
    @ColumnInfo(name = "title") val title: String,
    @ColumnInfo(name = "body") val body: String,
    @ColumnInfo(name = "aliases") val aliases: String
)
