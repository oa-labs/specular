package com.specular.android.data

import com.specular.android.data.local.FrontmatterParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FrontmatterParserTest {
    @Test fun parsesIdAndTitle() {
        val raw = """
---
id: 01kxp66n18p7vt6b5rsmd1taqy
---
# Barry Kaufman

- Type: #person
""".trimIndent()
        val p = FrontmatterParser.parse("barry-kaufman.md", raw)
        assertEquals("01kxp66n18p7vt6b5rsmd1taqy", p.id)
        assertEquals("Barry Kaufman", p.title)
    }

    @Test fun typeOnlyNoteGetsEmptySnippetWithoutNeedingAi() {
        val raw = """
            ---
            id: 01kxp66mygrnkxxq3wy79v1b1k
            ---
            # jackie@pennywise.tax

            - Type: #person
        """.trimIndent()

        val p = FrontmatterParser.parse("jackie-pennywise-tax.md", raw)

        assertEquals(
            FrontmatterParser.EMPTY_NOTE_SNIPPET,
            FrontmatterParser.snippetOrEmpty(p.body, p.snippet)
        )
        assertTrue(FrontmatterParser.isEmptySnippetContent(FrontmatterParser.snippetContent(p.body)))
    }

    @Test fun removesTypeMetadataBeforeAiSnippetGeneration() {
        val body = "# A person\n\n- Type: #person\n\nMet at the conference."

        assertEquals("Met at the conference.", FrontmatterParser.aiSnippetContent(body))
    }

    @Test fun substantiveNoteIsNotClassifiedAsEmpty() {
        val body = "# A person\n\n- Type: #person\n\nMet at the conference."

        assertEquals(null, FrontmatterParser.snippetOrEmpty(body, null))
    }

    @Test fun parsesAliases() {
        val raw = """
---
id: 01kyjm26ksqg9fd40ccxy08pcm
aliases:
  - OLLI - University of Pitt
---
# OLLI - University of Pitt Program
""".trimIndent()
        val p = FrontmatterParser.parse("olli.md", raw)
        assertEquals(listOf("OLLI - University of Pitt"), p.aliases)
    }

    @Test fun dailyWithoutFrontmatterUsesPathAsId() {
        val raw = "- Try out Quill\n"
        val p = FrontmatterParser.parse("daily/2026-07-28.md", raw)
        assertEquals("daily/2026-07-28.md", p.id)
    }

    @Test fun legacyListNoteWithoutMetadataIsSafeToParse() {
        val raw = """
            - Try out Quill for meeting recordings - https://github.com/digimata/quill
            - And maybe parrot for voice to text - https://github.com/digimata/parrot
        """.trimIndent()

        val p = FrontmatterParser.parse("meeting-recording-tools.md", raw)

        assertEquals(null, p.id)
        assertEquals("Meeting Recording Tools", p.title)
        assertEquals(raw, p.body)
        assertEquals("meeting-recording-tools", FrontmatterParser.identityFor("meeting-recording-tools.md", p.id))
    }

    @Test fun addsMissingIdWithoutDroppingExistingMetadata() {
        val frontmatter = """
            aliases:
              - Recording tools
            custom: retained
        """.trimIndent()

        val updated = FrontmatterParser.upsertIdInFrontmatter(frontmatter, "meeting-recording-tools")

        assertTrue(updated.startsWith("id: meeting-recording-tools\n"))
        assertTrue(updated.contains("aliases:"))
        assertTrue(updated.contains("custom: retained"))
    }

    @Test fun snippetWriteRepairsMissingIdInExistingFrontmatter() {
        val raw = """
            ---
            aliases:
              - Recording tools
            ---
            - Try out Quill
            - And maybe parrot
        """.trimIndent()

        val updated = FrontmatterParser.upsertSnippet("meeting-recording-tools.md", raw, "Voice transcription tools")
        val parsed = FrontmatterParser.parse("meeting-recording-tools.md", updated)

        assertEquals("meeting-recording-tools", parsed.id)
        assertEquals("Voice transcription tools", parsed.snippet)
        assertTrue(updated.contains("aliases:"))
    }

    @Test fun parsesAndUpsertsSnippetWithoutDroppingMetadata() {
        val raw = """
            ---
            id: 01snippet
            custom: retained
            ---
            # A title

            Body text.
        """.trimIndent()

        val withSnippet = FrontmatterParser.upsertSnippet("note.md", raw, "Project planning")
        val parsed = FrontmatterParser.parse("note.md", withSnippet)

        assertEquals("Project planning", parsed.snippet)
        assertEquals("A title", parsed.title)
        assertTrue(withSnippet.contains("custom: retained"))
    }

    @Test fun generateRoundTrip() {
        val gen = FrontmatterParser.generateFrontmatter("01abc", listOf("Alias"))
        assertNotNull(gen)
        assert(gen.contains("id: 01abc"))
        assert(gen.contains("Alias"))
    }
}
