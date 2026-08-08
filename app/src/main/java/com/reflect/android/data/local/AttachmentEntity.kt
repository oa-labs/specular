package com.specular.android.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

/** Binary repository file referenced by Markdown in `attachments/` or `assets/`. */
@Entity(tableName = "attachments")
data class AttachmentEntity(
    @PrimaryKey val path: String,
    val mimeType: String?,
    val lastRemoteSha: String?,
    val isDirty: Boolean = false,
    val updatedAt: Long = System.currentTimeMillis()
)
