package dev.adityamittal.k.backup

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dev.adityamittal.k.work.HeadlessWorker
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Daily encrypted Drive backup: `backupBackgroundMain` seals the database and
 * uploads it. First run is aimed at the next 03:00; WorkManager drifts it.
 */
class BackupWorker(context: Context, params: WorkerParameters) :
    HeadlessWorker(context, params, "backupBackgroundMain", 9 * 60_000L) {

    companion object {
        private const val WORK_NAME = "k.backup.daily"

        /** KEEP: re-scheduling on every app open must not push the run back. */
        fun schedule(context: Context, on: Boolean) {
            val wm = WorkManager.getInstance(context)
            if (!on) {
                wm.cancelUniqueWork(WORK_NAME)
                return
            }
            val request = PeriodicWorkRequestBuilder<BackupWorker>(1, TimeUnit.DAYS)
                .setInitialDelay(untilNext3am(), TimeUnit.MILLISECONDS)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .setRequiresBatteryNotLow(true)
                        .build(),
                ).build()
            wm.enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        private fun untilNext3am(): Long {
            val now = Calendar.getInstance()
            val next = (now.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, 3)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (!after(now)) add(Calendar.DAY_OF_MONTH, 1)
            }
            return next.timeInMillis - now.timeInMillis
        }
    }
}
