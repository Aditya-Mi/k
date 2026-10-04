package dev.adityamittal.k.sms

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Tracks whether a foreground Flutter UI is listening for new SMS.
 * Events carry no content — just "queue has items, drain it".
 */
object SmsEventHub : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: EventChannel.EventSink? = null

    val hasListener: Boolean get() = sink != null

    /** True if a live app was told; false means nobody is listening. */
    fun notifyPending(): Boolean {
        val s = sink ?: return false
        main.post { s.success("pending") }
        return true
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }
}
