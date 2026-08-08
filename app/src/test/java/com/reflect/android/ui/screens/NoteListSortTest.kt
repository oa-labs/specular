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

    @Test fun `places pinned notes first while preserving the selected sort`() {
        val notes = listOf(
            note("Zulu", 1, isPinned = true),
            note("Newest", 4),
            note("Alpha", 2, isPinned = true),
            note("Middle", 3)
        )

        assertEquals(
            listOf("Alpha", "Zulu", "Middle", "Newest"),
            sortNotes(notes, NoteSort.ALPHABETICAL).map { it.title }
        )
        assertEquals(
            listOf("Alpha", "Zulu", "Newest", "Middle"),
            sortNotes(notes, NoteSort.LAST_UPDATED).map { it.title }
        )
    }

    @Test fun `shows labels for root folders except assets and attachments`() {
        assertEquals("daily", noteFolderLabel(note("Today", 1, path = "daily/2026-08-08.md")))
        assertEquals("meetings", noteFolderLabel(note("Standup", 1, path = "meetings/standup.md")))
        assertEquals("projects", noteFolderLabel(note("Plan", 1, path = "projects/alpha/plan.md")))
        assertEquals(null, noteFolderLabel(note("Image", 1, path = "assets/logo.md")))
        assertEquals(null, noteFolderLabel(note("Photo", 1, path = "attachments/photo.md")))
        assertEquals(null, noteFolderLabel(note("Regular", 1)))
    }

    @Test fun `lists available note folders alphabetically without duplicates`() {
        val notes = listOf(
            note("Standup", 1, path = "meeting/standup.md"),
            note("Today", 1, path = "daily/2026-08-08.md"),
            note("Another standup", 1, path = "meeting/another.md"),
            note("Root note", 1),
            note("Image", 1, path = "assets/logo.md")
        )

        assertEquals(listOf("daily", "meeting"), noteFolders(notes))
    }

    @Test fun `filters deselected folders while retaining root notes`() {
        val notes = listOf(
            note("Today", 1, path = "daily/2026-08-08.md"),
            note("Standup", 1, path = "meeting/standup.md"),
            note("Root note", 1)
        )

        assertEquals(
            listOf("Standup", "Root note"),
            filterNotesByFolders(notes, setOf("daily")).map { it.title }
        )
    }

    private fun note(
        title: String,
        updatedAt: Long,
        isDaily: Boolean = false,
        isPinned: Boolean = false,
        path: String = "$title.md"
    ) = NoteListItem(
        id = title,
        title = title,
        path = path,
        snippet = null,
        isDaily = isDaily,
        isDirty = false,
        isConflict = false,
        isPinned = isPinned,
        updatedAt = updatedAt
    )
}
