package com.specular.android.domain.model

/** Lightweight task-list row, served directly by the local todo index. */
data class TodoListItem(
    val noteId: String,
    val taskIndex: Int,
    val text: String,
    val isCompleted: Boolean,
    val noteTitle: String
)

enum class TodoFilter { OPEN, COMPLETED, ALL }
