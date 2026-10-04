package dev.adityamittal.k.work

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import dev.adityamittal.k.sms.SmsChannel
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Periodic work that boots a headless Flutter engine on [entrypoint] (a
 * `@pragma('vm:entry-point')` function in `lib/main.dart`) and waits for it
 * to report back via `backgroundDone` on `k/sms`.
 */
abstract class HeadlessWorker(
    context: Context,
    params: WorkerParameters,
    private val entrypoint: String,
    private val timeoutMs: Long,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val ok = withContext(Dispatchers.Main) { runHeadless() }
        // Periodic work: a failed run just waits for the next period.
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
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), entrypoint),
            )
            withTimeoutOrNull(timeoutMs) { done.await() } ?: run {
                Log.w("k.HeadlessWorker", "$entrypoint timed out")
                false
            }
        } finally {
            channel.dispose()
            engine.destroy()
        }
    }
}
