package com.specular.android.ui.screens

import com.specular.android.domain.model.NoteListItem
import org.junit.Assert.assertEquals
import org.junit.Test

class EditorCreationTest {
    @Test fun `offers only user folders when creating a regular note`() {
        val folders = creationFolders(
            listOf(
                note("daily/2026-08-08.md"),
                note("Meetings/standup.md"),
                note("meetings/retro.md"),
                note("projects/specular.md"),
                note("assets/pasted-image.md"),
                note("attachments/photo.md"),
                note("root-note.md")
            )
        )

        assertEquals(listOf("Meetings", "projects"), folders)
    }

    private fun note(path: String) = NoteListItem(
        id = path,
        title = path,
        path = path,
        snippet = null,
        isDaily = path.startsWith("daily/"),
        isDirty = false,
        isConflict = false
    )
}
