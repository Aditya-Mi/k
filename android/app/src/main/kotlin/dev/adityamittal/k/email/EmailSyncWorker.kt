package dev.adityamittal.k.email

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dev.adityamittal.k.sms.SmsChannel
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit

/**
 * Hourly bank-mail check while the app is closed: boots a headless Flutter
 * engine on `emailBackgroundMain`, which syncs every inbox through the normal
 * ingestion pipeline and reports back via `backgroundDone` on `k/sms`.
 */
class EmailSyncWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val ok = withContext(Dispatchers.Main) { runHeadless() }
        // Periodic work: a failed run just waits for the next hour.
        return if (ok) Result.success() else Result.failure()
    }

    private suspend fun runHeadless(): Boolean {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val done = CompletableDeferred<Boolean>()
        val engine = FlutterEngine(applicationContext)
        val channel = SmsChannel(applicationContext, engine.dartExecutor.binaryMessenger) {
            done.complete(it)
        }
        return try {
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRYPOINT),
            )
            withTimeoutOrNull(TIMEOUT_MS) { done.await() } ?: run {
                Log.w(TAG, "headless email sync timed out")
                false
            }
        } finally {
            channel.dispose()
            engine.destroy()
        }
    }

    companion object {
        private const val TAG = "k.EmailWorker"
        private const val WORK_NAME = "k.email.sync"
        private const val ENTRYPOINT = "emailBackgroundMain"
        private const val TIMEOUT_MS = 5 * 60_000L

        /** On when at least one inbox is connected; KEEP leaves the cadence alone. */
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
