package com.specular.android.data.local

/**
 * Parses Reflect markdown per contract in docs/reflect-contract.md.
 * Format:
 * ---
 * id: 01kxp66n18p7vt6b5rsmd1taqy
 * aliases:
 *   - OLLI - University of Pitt
 * ---
 * # Title
 * Body...
 *
 * Daily notes (daily/YYYY-MM-DD.md) may have no frontmatter — path is identity.
 */
object FrontmatterParser {

    data class Parsed(
        val id: String?,
        val aliases: List<String>,
        val title: String,
        val body: String,
        val rawFrontmatter: String?,
        val rawMarkdown: String
    )

    private val idRegex = Regex("""^\s*id:\s*(\S+)\s*$""", RegexOption.MULTILINE)
    private val titleRegex = Regex("""^#\s+(.+)$""", RegexOption.MULTILINE)

    fun parse(path: String, raw: String): Parsed {
        val trimmed = raw.trimStart()
        if (trimmed.startsWith("---")) {
            val end = trimmed.indexOf("\n---", 3)
            if (end != -1) {
                val frontmatterBlock = trimmed.substring(3, end).trim()
                val bodyWithTitle = trimmed.substring(end + 4).trimStart()
                val id = idRegex.find(frontmatterBlock)?.groupValues?.get(1)
                // aliases: lines after "aliases:" that start with "  - "
                val aliases = mutableListOf<String>()
                val lines = frontmatterBlock.lines()
                var inAliases = false
                for (line in lines) {
                    if (line.trim() == "aliases:") { inAliases = true; continue }
                    if (inAliases) {
                        val m = Regex("""^\s*-\s+(.+)$""").find(line)
                        if (m != null) aliases.add(m.groupValues[1].trim())
                        else if (line.trim().isNotEmpty() && !line.startsWith(" ")) {
                            inAliases = false
                        }
                    }
                }
                val title = titleRegex.find(bodyWithTitle)?.groupValues?.get(1)?.trim()
                    ?: deriveTitleFromPath(path)
                return Parsed(
                    id = id?.trim(),
                    aliases = aliases,
                    title = title,
                    body = bodyWithTitle,
                    rawFrontmatter = frontmatterBlock,
                    rawMarkdown = raw
                )
            }
        }
        // No frontmatter
        val title = titleRegex.find(raw)?.groupValues?.get(1)?.trim()
            ?: deriveTitleFromPath(path)
        val idFromPath = if (path.startsWith("daily/")) path else null
        return Parsed(
            id = idFromPath,
            aliases = emptyList(),
            title = title,
            body = raw.trim(),
            rawFrontmatter = null,
            rawMarkdown = raw
        )
    }

    private fun deriveTitleFromPath(path: String): String {
        return path.substringAfterLast("/")
            .removeSuffix(".md")
            .split("-", "_")
            .joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }
    }

    fun generateFrontmatter(id: String, aliases: List<String> = emptyList()): String {
        val sb = StringBuilder()
        sb.append("---\n")
        sb.append("id: ").append(id).append("\n")
        if (aliases.isNotEmpty()) {
            sb.append("aliases:\n")
            aliases.forEach { sb.append("  - ").append(it).append("\n") }
        }
        sb.append("---\n")
        return sb.toString()
    }
}
