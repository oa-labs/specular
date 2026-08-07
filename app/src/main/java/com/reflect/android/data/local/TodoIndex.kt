package com.specular.android.data.local

import javax.inject.Inject
import javax.inject.Singleton

private val taskPattern = Regex(
    """(?m)^[ \t]*(?:[-+*]|\d+[.)])[ \t]+\[([ xX])\][ \t]*(.*)$"""
)

/** Parses the Markdown task syntax that the detail renderer already supports. */
@Singleton
class TodoIndex @Inject constructor() {
    fun extract(noteId: String, markdown: String): List<TodoEntity> =
        taskPattern.findAll(markdown).mapIndexed { index, match ->
            TodoEntity(
                noteId = noteId,
                taskIndex = index,
                text = match.groupValues[2].trim(),
                isCompleted = match.groupValues[1].equals("x", ignoreCase = true)
            )
        }.toList()

    fun count(markdown: String): Int = taskPattern.findAll(markdown).count()

    fun toggleAtIndex(markdown: String, taskIndex: Int): String {
        val match = taskPattern.findAll(markdown).elementAtOrNull(taskIndex) ?: return markdown
        val stateOffset = match.range.first + match.value.indexOf('[') + 1
        val nextState = if (match.groupValues[1] == " ") "x" else " "
        return markdown.replaceRange(stateOffset, stateOffset + 1, nextState)
    }
}

/** Shared with the Markdown renderer to keep click offsets aligned with the stored index. */
fun countTodoItems(markdown: String): Int = taskPattern.findAll(markdown).count()
