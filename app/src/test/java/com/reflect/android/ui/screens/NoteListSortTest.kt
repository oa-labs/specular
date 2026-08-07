package com.specular.android.ui.screens

import com.specular.android.domain.model.NoteListItem
import org.junit.Assert.assertEquals
import org.junit.Test

class NoteListSortTest {
    @Test fun `sorts notes by most recently updated first`() {
        val notes = listOf(note("Old", 1), note("Newest", 3), note("Middle", 2))

        assertEquals(
            listOf("Newest", "Middle", "Old"),
            sortNotes(notes, NoteSort.LAST_UPDATED).map { it.title }
        )
    }

    @Test fun `sorts notes alphabetically regardless of daily status`() {
        val notes = listOf(
            note("zebra", 3, isDaily = true),
            note("Apple", 1),
            note("middle", 2)
        )

        assertEquals(
            listOf("Apple", "middle", "zebra"),
            sortNotes(notes, NoteSort.ALPHABETICAL).map { it.title }
        )
    }

    private fun note(title: String, updatedAt: Long, isDaily: Boolean = false) = NoteListItem(
        id = title,
        title = title,
        path = "$title.md",
        snippet = null,
        isDaily = isDaily,
        isDirty = false,
        isConflict = false,
        updatedAt = updatedAt
    )
}
