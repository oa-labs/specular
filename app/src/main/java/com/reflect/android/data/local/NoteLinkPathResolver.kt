package com.specular.android.data.local

import java.net.URLDecoder
import java.nio.charset.StandardCharsets

/** Resolves a relative Markdown note link against the path of the current note. */
object NoteLinkPathResolver {
    private val schemePattern = Regex("^[A-Za-z][A-Za-z0-9+.-]*:")

    /**
     * Returns the repository-relative path of a linked Markdown note, or null when [destination]
     * is external, absolute, malformed, or not a Markdown file.
     */
    fun resolve(sourcePath: String, destination: String): String? {
        val rawPath = destination.substringBefore('#').substringBefore('?')
        if (rawPath.isBlank() ||
            rawPath.startsWith('/') ||
            rawPath.startsWith('\\') ||
            schemePattern.containsMatchIn(rawPath)
        ) return null

        val path = URLDecoder.decode(rawPath, StandardCharsets.UTF_8)
        if (!path.endsWith(".md", ignoreCase = true)) return null

        val components = mutableListOf<String>()
        val sourceDirectory = sourcePath.substringBeforeLast('/', missingDelimiterValue = "")
        (listOf(sourceDirectory, path)
            .filter { it.isNotEmpty() }
            .joinToString("/")
            .split('/'))
            .forEach { component ->
                when (component) {
                    "", "." -> Unit
                    ".." -> if (components.isEmpty()) return null else components.removeLast()
                    else -> components += component
                }
            }

        return components.joinToString("/").takeIf { it.isNotEmpty() }
    }
}
