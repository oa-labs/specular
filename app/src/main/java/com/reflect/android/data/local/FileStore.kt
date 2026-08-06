package com.reflect.android.data.local

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors GitHub repo files under app filesDir/notes/.
 * Canonical markdown on disk; Room is index. See docs/reflect-contract.md.
 */
@Singleton
class FileStore @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val root: File get() = File(context.filesDir, "notes").apply { mkdirs() }

    fun resolve(path: String): File = File(root, path).also { it.parentFile?.mkdirs() }

    fun read(path: String): String? {
        val f = resolve(path)
        return if (f.exists()) f.readText() else null
    }

    fun write(path: String, content: String) {
        resolve(path).writeText(content)
    }

    fun delete(path: String): Boolean = resolve(path).delete()

    fun listAllMarkdown(): List<Pair<String, String>> {
        if (!root.exists()) return emptyList()
        return root.walkTopDown()
            .filter { it.isFile && it.extension == "md" }
            .map { it.relativeTo(root).path to it.readText() }
            .toList()
    }

    fun exists(path: String): Boolean = resolve(path).exists()

    fun assetFile(name: String): File = File(root, "assets/$name").apply { parentFile?.mkdirs() }
}
