package com.specular.android.data

import com.specular.android.data.local.NoteLinkPathResolver
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NoteLinkPathResolverTest {
    @Test
    fun resolvesRelativeMarkdownLinkAgainstSourceDirectory() {
        assertEquals(
            "notes/AiAgentsDeepDiveApril7,2026.md",
            NoteLinkPathResolver.resolve(
                "daily/2026-04-07.md",
                "../notes/AiAgentsDeepDiveApril7,2026.md"
            )
        )
    }

    @Test
    fun resolvesEncodedPathsAndIgnoresAnAnchor() {
        assertEquals(
            "notes/Agent Notes.md",
            NoteLinkPathResolver.resolve("notes/source.md", "Agent%20Notes.md#summary")
        )
    }

    @Test
    fun resolvesLinksThatAscendPastRepositoryRootToTheRepository() {
        assertEquals(
            "notes/AiAgentsDeepDiveApril7,2026.md",
            NoteLinkPathResolver.resolve(
                "source.md",
                "../notes/AiAgentsDeepDiveApril7,2026.md"
            )
        )
    }

    @Test
    fun doesNotTreatWebLinksAsNotes() {
        assertNull(NoteLinkPathResolver.resolve("notes/source.md", "https://example.com/note.md"))
    }
}
