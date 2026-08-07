package com.specular.android.data.local

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/** A denormalized, queryable task-list item derived from a note's Markdown body. */
@Entity(
    tableName = "todo_index",
    primaryKeys = ["noteId", "taskIndex"],
    indices = [Index(value = ["isCompleted", "noteId"])]
)
data class TodoEntity(
    val noteId: String,
    val taskIndex: Int,
    val text: String,
    val isCompleted: Boolean
)

/** Records whether legacy notes have been parsed into [TodoEntity] rows. */
@Entity(tableName = "todo_index_state")
data class TodoIndexState(
    @PrimaryKey val id: Int = 0,
    val isReady: Boolean = false
)
