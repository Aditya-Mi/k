package dev.adityamittal.k.sms

import android.content.Context
import android.database.Cursor
import android.os.Build
import android.provider.Telephony
import android.telephony.SubscriptionManager

/**
 * Reads the system SMS inbox for first-run history and catch-up scans.
 * Paged by provider `_id` so Dart can keep a cursor of the last row it saw.
 */
class SmsInboxReader(private val context: Context) {

    /**
     * Business-sender inbox rows with `_id > afterId` and `date >= sinceMillis`,
     * oldest first. `scanned` lets Dart advance its cursor past filtered-out rows.
     */
    fun read(afterId: Long, sinceMillis: Long, limit: Int): Map<String, Any?> {
        val messages = mutableListOf<Map<String, Any?>>()
        var maxId = afterId
        var scanned = 0
        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            null,
            "${Telephony.Sms._ID} > ? AND ${Telephony.Sms.DATE} >= ?",
            arrayOf(afterId.toString(), sinceMillis.toString()),
            "${Telephony.Sms._ID} ASC LIMIT $limit",
        )?.use { c ->
            val idCol = c.getColumnIndexOrThrow(Telephony.Sms._ID)
            val addrCol = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyCol = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateCol = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            val sentCol = c.getColumnIndex(Telephony.Sms.DATE_SENT)
            val subCol = c.getColumnIndex(Telephony.Sms.SUBSCRIPTION_ID)
            // LIMIT rides on sortOrder; also stop here in case a provider ignores it.
            while (scanned < limit && c.moveToNext()) {
                scanned++
                val id = c.getLong(idCol)
                if (id > maxId) maxId = id
                val sender = c.getString(addrCol)
                if (!SenderFilter.isBusinessSender(sender)) continue
                messages += mapOf(
                    "providerId" to id,
                    "sender" to sender,
                    "body" to (c.getString(bodyCol) ?: ""),
                    "timestamp" to timestampOf(c, sentCol, dateCol),
                    "simSlot" to slotOf(c, subCol),
                )
            }
        }
        return mapOf("messages" to messages, "maxId" to maxId, "scanned" to scanned)
    }

    /** Highest inbox `_id` now — the cursor to start from when history is skipped. */
    fun maxId(): Long {
        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms._ID),
            null,
            null,
            "${Telephony.Sms._ID} DESC LIMIT 1",
        )?.use { c -> if (c.moveToFirst()) return c.getLong(0) }
        return 0
    }

    /** Prefer the service-centre time so it matches what [SmsReceiver] saw. */
    private fun timestampOf(c: Cursor, sentCol: Int, dateCol: Int): Long {
        val sent = if (sentCol >= 0) c.getLong(sentCol) else 0L
        return if (sent > 0) sent else c.getLong(dateCol)
    }

    private fun slotOf(c: Cursor, subCol: Int): Int? {
        if (subCol < 0 || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val subId = c.getInt(subCol)
        if (subId < 0) return null
        val slot = SubscriptionManager.getSlotIndex(subId)
        return if (slot >= 0) slot else null
    }
}
