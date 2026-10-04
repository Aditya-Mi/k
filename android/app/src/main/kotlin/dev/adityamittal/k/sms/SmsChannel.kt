package dev.adityamittal.k.sms

import android.content.Context
import dev.adityamittal.k.backup.BackupWorker
import dev.adityamittal.k.email.EmailSyncWorker
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Method channel `k/sms`, shared by the UI engine and the headless worker engine.
 *
 * - drainPending → queued live SMS (not removed until ackPending)
 * - ackPending(ids)
 * - readInbox(afterId, sinceMillis, limit) → {messages, maxId, scanned}
 * - maxInboxId → Long
 * - backgroundDone(ok) → worker engine only
 * - scheduleEmailSync({on, intervalMinutes}) → hourly bank-mail worker
 * - scheduleBackup(on) → daily Drive backup worker
 */
class SmsChannel(
    context: Context,
    messenger: BinaryMessenger,
    private val onBackgroundDone: ((Boolean) -> Unit)? = null,
) : MethodChannel.MethodCallHandler {
    private val ctx = context.applicationContext
    private val channel = MethodChannel(messenger, NAME)
    private val inbox = SmsInboxReader(ctx)
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() = channel.setMethodCallHandler(null)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "drainPending" -> io(result) { PendingSmsQueue.peekAll(ctx).map { it.toMap() } }
            "ackPending" -> io(result) {
                PendingSmsQueue.ack(ctx, call.arguments<List<String>>() ?: emptyList())
                null
            }
            "readInbox" -> io(result) {
                inbox.read(
                    afterId = call.longArg("afterId"),
                    sinceMillis = call.longArg("sinceMillis"),
                    limit = call.argument<Int>("limit") ?: 500,
                )
            }
            "maxInboxId" -> io(result) { inbox.maxId() }
            "scheduleEmailSync" -> {
                EmailSyncWorker.schedule(
                    ctx,
                    call.argument<Boolean>("on") ?: false,
                    call.longArg("intervalMinutes").takeIf { it > 0 } ?: 60L,
                )
                result.success(null)
            }
            "scheduleBackup" -> {
                BackupWorker.schedule(ctx, call.arguments<Boolean>() ?: false)
                result.success(null)
            }
            "backgroundDone" -> {
                onBackgroundDone?.invoke(call.arguments<Boolean>() ?: true)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Disk and content-provider work off the main thread; reply on it. */
    private fun io(result: MethodChannel.Result, block: () -> Any?) {
        ioPool.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("permission", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message, e.javaClass.simpleName) }
            }
        }
    }

    private fun MethodCall.longArg(name: String): Long =
        (argument<Any>(name) as? Number)?.toLong() ?: 0L

    companion object {
        const val NAME = "k/sms"
        const val EVENTS = "k/sms_events"
        private val ioPool = Executors.newSingleThreadExecutor()
    }
}
