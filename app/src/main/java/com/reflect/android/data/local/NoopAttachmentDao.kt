package com.specular.android.data.local

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

/** Keeps focused sync unit tests independent of Room attachment setup. */
object NoopAttachmentDao : AttachmentDao {
    override fun observeChangeToken(): Flow<Long?> = flowOf(null)
    override suspend fun getByPath(path: String): AttachmentEntity? = null
    override suspend fun getDirty(): List<AttachmentEntity> = emptyList()
    override suspend fun upsert(attachment: AttachmentEntity) = Unit
    override suspend fun deleteByPath(path: String) = Unit
}
