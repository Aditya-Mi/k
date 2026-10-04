package dev.adityamittal.k.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.telephony.SubscriptionManager
import android.util.Log

/**
 * SMS_RECEIVED → queue → live app (EventChannel) or a background worker.
 * Kept tiny: no parsing here, the Dart pipeline owns all of that.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return

        val simSlot = simSlotOf(context, intent)
        // A long SMS arrives as several parts in one broadcast; join per sender.
        parts.groupBy { it.originatingAddress ?: it.displayOriginatingAddress }
            .forEach { (sender, msgs) ->
                if (!SenderFilter.isBusinessSender(sender)) return@forEach
                val body = msgs.joinToString("") { it.messageBody ?: "" }
                val timestamp = msgs.first().timestampMillis
                PendingSmsQueue.add(
                    context,
                    PendingSms.create(sender!!, body, timestamp, simSlot),
                )
            }

        if (PendingSmsQueue.isEmpty(context)) return
        if (!SmsEventHub.notifyPending()) {
            SmsProcessWorker.enqueue(context)
        }
    }

    /** 0-based SIM slot, or null if the OEM does not say. */
    private fun simSlotOf(context: Context, intent: Intent): Int? {
        val extras = intent.extras ?: return null
        for (key in listOf(SLOT_INDEX, "slot", "simSlot", "slot_id", "simId")) {
            if (extras.containsKey(key)) {
                val v = extras.getInt(key, -1)
                if (v >= 0) return v
            }
        }
        val subId = extras.getInt(SUBSCRIPTION_INDEX, extras.getInt("subscription", -1))
        if (subId >= 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val slot = SubscriptionManager.getSlotIndex(subId)
            if (slot >= 0) return slot
        }
        Log.d(TAG, "no SIM slot in SMS intent")
        return null
    }

    companion object {
        private const val TAG = "k.SmsReceiver"
        private const val SLOT_INDEX = "android.telephony.extra.SLOT_INDEX"
        private const val SUBSCRIPTION_INDEX = "android.telephony.extra.SUBSCRIPTION_INDEX"
    }
}
