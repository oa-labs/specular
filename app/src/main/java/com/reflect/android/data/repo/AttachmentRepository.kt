package com.specular.android.data.repo

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.work.WorkManager
import com.specular.android.data.local.AttachmentDao
import com.specular.android.data.local.AttachmentEntity
import com.specular.android.data.local.FileStore
import com.specular.android.data.local.MarkdownAttachmentResolver
import com.specular.android.sync.SyncScheduler
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** Imports local images into the Reflect-compatible `attachments/` directory. */
@Singleton
class AttachmentRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val fileStore: FileStore,
    private val attachmentDao: AttachmentDao,
    private val workManager: WorkManager
) {
    suspend fun importImage(source: Uri, notePath: String): String = withContext(Dispatchers.IO) {
        val mimeType = context.contentResolver.getType(source) ?: "image/jpeg"
        require(mimeType.startsWith("image/")) { "Choose an image file" }
        val extension = extensionFor(source, mimeType)
        val path = "attachments/${UUID.randomUUID()}.$extension"
        val bytes = context.contentResolver.openInputStream(source)?.use { it.readBytes() }
            ?: error("Unable to read selected image")
        fileStore.writeBytes(path, bytes)
        attachmentDao.upsert(
            AttachmentEntity(path = path, mimeType = mimeType, lastRemoteSha = null, isDirty = true)
        )
        SyncScheduler.enqueueDebouncedSync(workManager)
        MarkdownAttachmentResolver.referenceFor(notePath, path)
    }

    private fun extensionFor(uri: Uri, mimeType: String): String {
        val displayName = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                cursor.takeIf { it.moveToFirst() }?.getString(0)
            }
        val fromName = displayName?.substringAfterLast('.', "")?.lowercase().orEmpty()
        if (fromName in supportedExtensions) return fromName
        return when (mimeType) {
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            "image/heic", "image/heif" -> "heic"
            else -> "jpg"
        }
    }

    private companion object {
        val supportedExtensions = setOf("jpg", "jpeg", "png", "webp", "gif", "heic", "heif")
    }
}
