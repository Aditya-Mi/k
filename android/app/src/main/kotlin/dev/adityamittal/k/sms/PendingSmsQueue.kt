package dev.adityamittal.k.sms

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** An SMS captured by [SmsReceiver] and not yet stored by the Dart side. */
data class PendingSms(
    val id: String,
    val sender: String,
    val body: String,
    /** Service-centre timestamp (ms) — same value the inbox keeps in `date_sent`. */
    val timestamp: Long,
    val simSlot: Int?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "sender" to sender,
        "body" to body,
        "timestamp" to timestamp,
        "simSlot" to simSlot,
    )

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("sender", sender)
        .put("body", body)
        .put("timestamp", timestamp)
        .put("simSlot", simSlot ?: JSONObject.NULL)

    companion object {
        fun create(sender: String, body: String, timestamp: Long, simSlot: Int?) =
            PendingSms(UUID.randomUUID().toString(), sender, body, timestamp, simSlot)

        fun fromJson(o: JSONObject) = PendingSms(
            id = o.getString("id"),
            sender = o.getString("sender"),
            body = o.getString("body"),
            timestamp = o.getLong("timestamp"),
            simSlot = if (o.isNull("simSlot")) null else o.getInt("simSlot"),
        )
    }
}

/**
 * Durable hand-off between the receiver and Dart, in app-private storage.
 * Entries are removed only after Dart acks them (stored in the encrypted DB),
 * so a crash or killed worker never loses a message.
 */
object PendingSmsQueue {
    private const val FILE_NAME = "pending_sms.json"
    private val lock = Any()

    private fun file(ctx: Context) = File(ctx.noBackupFilesDir, FILE_NAME)

    fun add(ctx: Context, sms: PendingSms) = synchronized(lock) {
        write(ctx, read(ctx) + sms)
    }

    fun peekAll(ctx: Context): List<PendingSms> = synchronized(lock) { read(ctx) }

    fun isEmpty(ctx: Context): Boolean = peekAll(ctx).isEmpty()

    fun ack(ctx: Context, ids: Collection<String>) = synchronized(lock) {
        if (ids.isEmpty()) return@synchronized
        val keep = read(ctx).filterNot { it.id in ids }
        write(ctx, keep)
    }

    private fun read(ctx: Context): List<PendingSms> {
        val f = file(ctx)
        if (!f.exists()) return emptyList()
        return try {
            val arr = JSONArray(f.readText())
            List(arr.length()) { PendingSms.fromJson(arr.getJSONObject(it)) }
        } catch (e: Exception) {
            // Corrupt file: keep a copy for inspection rather than silently dropping it.
            f.renameTo(File(f.parentFile, "$FILE_NAME.corrupt-${System.currentTimeMillis()}"))
            emptyList()
        }
    }

    private fun write(ctx: Context, items: List<PendingSms>) {
        val f = file(ctx)
        val tmp = File(f.parentFile, "$FILE_NAME.tmp")
        val arr = JSONArray().apply { items.forEach { put(it.toJson()) } }
        tmp.writeText(arr.toString())
        if (!tmp.renameTo(f)) {
            f.delete()
            tmp.renameTo(f)
        }
    }
}
