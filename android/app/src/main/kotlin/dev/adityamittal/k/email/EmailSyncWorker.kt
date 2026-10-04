package dev.adityamittal.k.email

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dev.adityamittal.k.work.HeadlessWorker
import java.util.concurrent.TimeUnit

/**
 * Hourly bank-mail check while the app is closed: `emailBackgroundMain` syncs
 * every inbox through the normal ingestion pipeline.
 */
class EmailSyncWorker(context: Context, params: WorkerParameters) :
    HeadlessWorker(context, params, "emailBackgroundMain", 5 * 60_000L) {

    companion object {
        private const val WORK_NAME = "k.email.sync"

        /** On when at least one inbox is connected. */
        fun schedule(context: Context, on: Boolean, intervalMinutes: Long) {
            val wm = WorkManager.getInstance(context)
            if (!on) {
                wm.cancelUniqueWork(WORK_NAME)
                return
            }
            val request = PeriodicWorkRequestBuilder<EmailSyncWorker>(
                intervalMinutes.coerceAtLeast(15), TimeUnit.MINUTES,
            ).setConstraints(
                Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
            ).build()
            wm.enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
        }
    }
}
