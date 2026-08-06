package com.reflect.android.data.local

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
    val isDaily: Boolean,
    val lastRemoteSha: String?,
    val isDirty: Boolean = false,
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
