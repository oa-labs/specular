package com.reflect.android.data

import com.reflect.android.data.local.FrontmatterParser
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
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

    @Test fun generateRoundTrip() {
        val gen = FrontmatterParser.generateFrontmatter("01abc", listOf("Alias"))
        assertNotNull(gen)
        assert(gen.contains("id: 01abc"))
        assert(gen.contains("Alias"))
    }
}
