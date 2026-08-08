package com.specular.android.sync

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
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
            // The periodic worker is registered before the user has configured GitHub.
            // Treat that idle state as successful so it is ready for a later configuration.
            is SyncEngine.Result.NotConfigured -> Result.success()
            is SyncEngine.Result.Error -> Result.retry()
        }
    }
}
