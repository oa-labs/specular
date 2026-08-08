package com.specular.android.data.local

/** Resolves repository-local Markdown attachment links without allowing traversal above root. */
object MarkdownAttachmentResolver {
    private val linkPattern = Regex("""!?\[[^]]*]\(([^)\s]+)(?:\s+[^)]*)?\)""")

    fun referencedPaths(notePath: String, markdown: String): Set<String> =
        linkPattern.findAll(markdown)
            .mapNotNull { resolve(notePath, it.groupValues[1].removeSurrounding("<", ">")) }
            .toSet()

    fun resolve(notePath: String, destination: String): String? {
        val value = destination.substringBefore('#').substringBefore('?').trim()
        if (value.isBlank() || value.contains("://") || value.startsWith("file:") ||
            value.startsWith("content:") || value.startsWith("data:")
        ) return null

        // Reflect repositories contain both root-relative-style assets/ links and
        // conventional relative ../attachments/ links.
        val start = when {
            value.startsWith("attachments/") || value.startsWith("assets/") -> emptyList()
            else -> notePath.substringBeforeLast('/', "").split('/').filter { it.isNotEmpty() }
        }
        val parts = start.toMutableList()
        for (part in value.split('/')) {
            when (part) {
                "", "." -> Unit
                ".." -> if (parts.isNotEmpty()) parts.removeLast() else return null
                else -> parts += part
            }
        }
        val path = parts.joinToString("/")
        return path.takeIf(::isAttachmentPath)
    }

    fun referenceFor(notePath: String, attachmentPath: String): String {
        require(isAttachmentPath(attachmentPath)) { "Unsupported attachment path: $attachmentPath" }
        val noteParent = notePath.substringBeforeLast('/', "").split('/').filter { it.isNotEmpty() }
        val target = attachmentPath.split('/')
        var shared = 0
        while (shared < noteParent.size && shared < target.size && noteParent[shared] == target[shared]) shared++
        return List(noteParent.size - shared) { ".." }
            .plus(target.drop(shared))
            .joinToString("/")
    }

    fun isAttachmentPath(path: String): Boolean =
        (path.startsWith("attachments/") || path.startsWith("assets/")) &&
            !path.endsWith(".reflect.md")
}
