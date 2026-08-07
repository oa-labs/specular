package com.specular.android.sync

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val syncEngine: SyncEngine
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        return when (val r = syncEngine.sync()) {
            is SyncEngine.Result.Success -> Result.success()
            is SyncEngine.Result.NotConfigured -> Result.failure(
                workDataOf(ERROR_MESSAGE to "GitHub sync is not configured. Add a PAT with Contents: Read and write permission in Settings.")
            )
            is SyncEngine.Result.Error -> Result.failure(workDataOf(ERROR_MESSAGE to r.message))
        }
    }

    companion object {
        const val ERROR_MESSAGE = "sync_error_message"
    }
}
