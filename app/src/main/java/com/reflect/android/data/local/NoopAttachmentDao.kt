package com.specular.android.data.local

/** Keeps focused sync unit tests independent of Room attachment setup. */
object NoopAttachmentDao : AttachmentDao {
    override suspend fun getByPath(path: String): AttachmentEntity? = null
    override suspend fun getDirty(): List<AttachmentEntity> = emptyList()
    override suspend fun upsert(attachment: AttachmentEntity) = Unit
    override suspend fun deleteByPath(path: String) = Unit
}
