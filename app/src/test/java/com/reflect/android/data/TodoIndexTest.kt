package com.specular.android.data

import com.specular.android.data.local.TodoIndex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TodoIndexTest {
    private val index = TodoIndex()

    @Test
    fun extractsSupportedMarkdownTasksInSourceOrder() {
        val tasks = index.extract(
            "note-1",
            """
                - [ ] First task
                  - [X] Nested task
                1. [x] Numbered task
                + [ ] Final task
            """.trimIndent()
        )

        assertEquals(listOf("First task", "Nested task", "Numbered task", "Final task"), tasks.map { it.text })
        assertEquals(listOf(false, true, true, false), tasks.map { it.isCompleted })
        assertEquals(listOf(0, 1, 2, 3), tasks.map { it.taskIndex })
        assertTrue(tasks.all { it.noteId == "note-1" })
    }

    @Test
    fun toggleChangesOnlyTheRequestedTaskMarker() {
        val markdown = "- [ ] First\n- [x] Second\n"

        val updated = index.toggleAtIndex(markdown, 1)

        assertEquals("- [ ] First\n- [ ] Second\n", updated)
        assertEquals(markdown, index.toggleAtIndex(markdown, 5))
        assertFalse(index.extract("note", updated)[1].isCompleted)
    }
}
