package com.specular.android.sync

import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/** Schedules GitHub syncs without requiring the app UI to be open. */
object SyncScheduler {
    private const val PERIODIC_SYNC_WORK_NAME = "github_periodic_sync"
    private const val IMMEDIATE_SYNC_WORK_NAME = "github_immediate_sync"
    private const val SYNC_WORK_TAG = "github_sync"
    private const val SYNC_INTERVAL_MINUTES = 15L

    private val connectedNetwork = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .build()

    fun schedulePeriodic(workManager: WorkManager) {
        val request = PeriodicWorkRequestBuilder<SyncWorker>(SYNC_INTERVAL_MINUTES, TimeUnit.MINUTES)
            .setConstraints(connectedNetwork)
            .addTag(SYNC_WORK_TAG)
            .build()

        workManager.enqueueUniquePeriodicWork(
            PERIODIC_SYNC_WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request
        )
    }

    /** Queues an initial sync after GitHub credentials have been verified. */
    fun enqueueInitialSync(workManager: WorkManager) {
        val request = OneTimeWorkRequestBuilder<SyncWorker>()
            .setConstraints(connectedNetwork)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
            .addTag(SYNC_WORK_TAG)
            .build()

        workManager.enqueueUniqueWork(
            IMMEDIATE_SYNC_WORK_NAME,
            ExistingWorkPolicy.KEEP,
            request
        )
    }
}
