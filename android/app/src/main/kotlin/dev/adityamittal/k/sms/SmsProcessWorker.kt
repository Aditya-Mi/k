package dev.adityamittal.k.sms

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit

/**
 * Stores queued SMS when the app is not running: boots a headless Flutter
 * engine on the Dart entrypoint `smsBackgroundMain`, which drains the queue
 * through the normal ingestion pipeline and reports back via `backgroundDone`.
 */
class SmsProcessWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        if (PendingSmsQueue.isEmpty(applicationContext)) return Result.success()
        // The UI came up meanwhile and will drain the queue itself.
        if (SmsEventHub.notifyPending()) return Result.success()

        val ok = withContext(Dispatchers.Main) { runHeadless() }
        return when {
            ok && PendingSmsQueue.isEmpty(applicationContext) -> Result.success()
            runAttemptCount < MAX_ATTEMPTS -> Result.retry()
            else -> Result.failure() // left in the queue; next app open drains it
        }
    }

    private suspend fun runHeadless(): Boolean {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val done = CompletableDeferred<Boolean>()
        // Auto-registers plugins (secure storage, path_provider) for the DB.
        val engine = FlutterEngine(applicationContext)
        val channel = SmsChannel(applicationContext, engine.dartExecutor.binaryMessenger) {
            done.complete(it)
        }
        return try {
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRYPOINT),
            )
            withTimeoutOrNull(TIMEOUT_MS) { done.await() } ?: run {
                Log.w(TAG, "headless ingestion timed out")
                false
            }
        } finally {
            channel.dispose()
            engine.destroy()
        }
    }

    /** Only used for expedited work on Android < 12. */
    override suspend fun getForegroundInfo(): ForegroundInfo {
        val nm = applicationContext.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Logging payments", NotificationManager.IMPORTANCE_MIN),
            )
        }
        val notification = Notification.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("Logging a payment")
            .build()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        private const val TAG = "k.SmsWorker"
        private const val WORK_NAME = "k.sms.process"
        private const val ENTRYPOINT = "smsBackgroundMain"
        private const val CHANNEL_ID = "k.sms.background"
        private const val NOTIFICATION_ID = 4101
        private const val TIMEOUT_MS = 60_000L
        private const val MAX_ATTEMPTS = 5

        fun enqueue(context: Context) {
            val request = OneTimeWorkRequestBuilder<SmsProcessWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            // Append so an SMS arriving mid-run is picked up by a follow-up run.
            WorkManager.getInstance(context)
                .enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        }
    }
}
