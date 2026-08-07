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
        val snippet: String?,
        val body: String,
        val rawFrontmatter: String?,
        val rawMarkdown: String
    )

    private val idRegex = Regex("""^\s*id:\s*(\S+)\s*$""", RegexOption.MULTILINE)
    private val titleRegex = Regex("""^#\s+(.+)$""", RegexOption.MULTILINE)
    private val snippetRegex = Regex("""^\s*snippet:\s*(.*?)\s*$""", RegexOption.MULTILINE)

    fun parse(path: String, raw: String): Parsed {
        val trimmed = raw.trimStart()
        if (trimmed.startsWith("---")) {
            val end = trimmed.indexOf("\n---", 3)
            if (end != -1) {
                val frontmatterBlock = trimmed.substring(3, end).trim()
                val bodyWithTitle = trimmed.substring(end + 4).trimStart()
                val id = idRegex.find(frontmatterBlock)?.groupValues?.get(1)
                val snippet = snippetRegex.find(frontmatterBlock)?.groupValues?.get(1)
                    ?.let(::decodeScalar)
                    ?.takeIf { it.isNotBlank() }
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
                    snippet = snippet,
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
            snippet = null,
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

    fun generateFrontmatter(
        id: String,
        aliases: List<String> = emptyList(),
        snippet: String? = null
    ): String {
        val sb = StringBuilder()
        sb.append("---\n")
        sb.append("id: ").append(id).append("\n")
        if (aliases.isNotEmpty()) {
            sb.append("aliases:\n")
            aliases.forEach { sb.append("  - ").append(it).append("\n") }
        }
        if (!snippet.isNullOrBlank()) {
            sb.append("snippet: ").append(encodeScalar(snippet)).append("\n")
        }
        sb.append("---\n")
        return sb.toString()
    }

    /** Adds or replaces only the snippet field, preserving all other metadata. */
    fun upsertSnippet(path: String, raw: String, snippet: String): String {
        val trimmed = raw.trimStart()
        if (trimmed.startsWith("---")) {
            val offset = raw.length - trimmed.length
            val end = trimmed.indexOf("\n---", 3)
            if (end != -1) {
                val frontmatterStart = offset + 3
                val frontmatterEnd = offset + end
                val frontmatter = raw.substring(frontmatterStart, frontmatterEnd)
                val replacement = "snippet: ${encodeScalar(snippet)}"
                val updatedFrontmatter = frontmatter
                    .lineSequence()
                    .map { line -> if (snippetRegex.matches(line)) replacement else line }
                    .toList()
                    .let { lines ->
                        if (lines.none { snippetRegex.matches(it) }) lines + replacement else lines
                    }
                    .joinToString("\n")
                return raw.substring(0, frontmatterStart) + updatedFrontmatter + raw.substring(frontmatterEnd)
            }
        }

        // Daily notes historically have no frontmatter. Add metadata without changing their body.
        return generateFrontmatter(if (path.startsWith("daily/")) path else path.removeSuffix(".md"), snippet = snippet) + raw
    }

    private fun encodeScalar(value: String): String =
        "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ").trim() + "\""

    private fun decodeScalar(value: String): String {
        val scalar = value.trim()
        if (scalar.length >= 2 && scalar.first() == '"' && scalar.last() == '"') {
            return scalar.substring(1, scalar.length - 1)
                .replace("\\\"", "\"")
                .replace("\\\\", "\\")
        }
        return scalar.removeSurrounding("'")
    }
}
