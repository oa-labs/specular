package com.reflect.android.domain.model

/**
 * Domain model — canonical identity is [id] (ULID from frontmatter).
 * Filename is a slug derived from title; path includes subdir if any (daily/, notes/).
 */
data class Note(
    val id: String,
    val title: String,
    val path: String, // e.g. "barry-kaufman.md" or "daily/2026-07-28.md" or "notes/how-to-use-reflect.md"
    val rawMarkdown: String,
    val bodyMarkdown: String, // without frontmatter
    val aliases: List<String> = emptyList(),
    val createdAt: Long? = null,
    val updatedAt: Long? = null,
    val isDaily: Boolean = path.startsWith("daily/"),
    val lastRemoteSha: String? = null,
    val isDirty: Boolean = false,
    val isConflict: Boolean = false
)

/**
 * Lightweight list item — avoids loading full body.
 */
data class NoteListItem(
    val id: String,
    val title: String,
    val path: String,
    val snippet: String,
    val isDaily: Boolean,
    val isDirty: Boolean,
    val isConflict: Boolean
)
