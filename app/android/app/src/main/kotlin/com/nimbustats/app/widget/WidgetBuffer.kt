package com.nimbustats.app.widget

import android.content.Context
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import org.json.JSONObject

/**
 * The widget's files under `filesDir` (spec §2.1), behind one lock.
 *
 * Every reader and writer runs in the app's process: widget broadcasts, the dialog, the drain job
 * and the channel. So a synchronized object is enough. An append writes one line and syncs it to
 * disk. Anything that removes lines or replaces the snapshot writes a temp file and renames it
 * over the original, so a crash leaves the old file, never half of one.
 */
object WidgetBuffer {
    private const val BUFFER = "widget_buffer.jsonl"
    private const val REJECTED = "widget_buffer.rejected.jsonl"
    private const val SNAPSHOT = "widget_snapshot.json"
    private const val VERSION = 1

    @Synchronized
    fun appendExpense(context: Context, atUtc: Long, amountMinor: Long, categoryId: String?) {
        require(amountMinor in 1..AmountParser.MAX_MINOR) { "amount $amountMinor is out of range" }
        append(
            context,
            line("expense", atUtc).put("amountMinor", amountMinor).put("categoryId", categoryId ?: JSONObject.NULL),
        )
    }

    @Synchronized
    fun appendTrackerTap(context: Context, atUtc: Long, trackerId: String) {
        append(context, line("tracker", atUtc).put("trackerId", trackerId))
    }

    /** Every pending line, raw. Nothing is removed (spec §2.3 step 1). */
    @Synchronized
    fun lines(context: Context): List<String> = readLines(file(context, BUFFER))

    /**
     * Tracker taps still waiting, for [PendingOverlay]. A line that does not read is left out
     * here. The drain rejects it, keeps it in the rejected file, and reports it (spec §2.3).
     */
    @Synchronized
    fun pendingTaps(context: Context): List<PendingTap> = lines(context).mapNotNull { raw ->
        runCatching {
            JSONObject(raw).takeIf { it.optString("kind") == "tracker" }
                ?.let { PendingTap(it.getString("trackerId"), it.getLong("atUtc")) }
        }.onFailure { Log.e(TAG, "unreadable buffer line", it) }.getOrNull()
    }

    @Synchronized
    fun writeSnapshot(context: Context, json: String) = replace(file(context, SNAPSHOT), json)

    @Synchronized
    fun readSnapshot(context: Context): String? = file(context, SNAPSHOT).takeIf { it.exists() }?.readText()

    /**
     * Spec §2.3 step 4, in one locked call:
     * 1. keeps the rejected lines with their reasons in `widget_buffer.rejected.jsonl`;
     * 2. writes the snapshot;
     * 3. drops the acked and rejected lines.
     *
     * One call is what keeps a tap from counting twice (in the snapshot and still pending) or not
     * at all.
     */
    @Synchronized
    fun commit(context: Context, snapshot: String, ackIds: Set<String>, rejected: Map<String, String>) {
        if (rejected.isNotEmpty()) {
            FileOutputStream(file(context, REJECTED), true).use { out ->
                for ((line, reason) in rejected) {
                    out.write((JSONObject().put("line", line).put("reason", reason).toString() + "\n").toByteArray())
                }
                out.fd.sync()
            }
        }
        replace(file(context, SNAPSHOT), snapshot)
        val kept = readLines(file(context, BUFFER)).filter { raw -> raw !in rejected && idOf(raw) !in ackIds }
        replace(file(context, BUFFER), kept.joinToString("") { "$it\n" })
    }

    private fun line(kind: String, atUtc: Long): JSONObject =
        JSONObject().put("v", VERSION).put("id", Uuid7.shared.next()).put("kind", kind).put("atUtc", atUtc)

    private fun append(context: Context, json: JSONObject) = appendLine(file(context, BUFFER), json.toString())

    /**
     * Appends [line] and syncs it to disk. Its callers hold the lock.
     *
     * A file whose last byte is not a newline ends in a line torn by a crash or power loss
     * mid-append. The new line then starts on a fresh line, so the drain rejects only the torn
     * line, never the tap that would have been glued onto it (D29).
     */
    internal fun appendLine(target: File, line: String) {
        val torn = target.length() > 0 && RandomAccessFile(target, "r").use { file ->
            file.seek(file.length() - 1)
            file.read() != '\n'.code
        }
        FileOutputStream(target, true).use { out ->
            out.write(((if (torn) "\n" else "") + line + "\n").toByteArray())
            out.fd.sync()
        }
    }

    private fun replace(target: File, content: String) {
        val temp = File(target.parentFile, "${target.name}.tmp")
        FileOutputStream(temp).use { out ->
            out.write(content.toByteArray())
            out.fd.sync()
        }
        if (!temp.renameTo(target)) throw IOException("could not replace ${target.name}")
    }

    private fun readLines(file: File): List<String> =
        if (file.exists()) file.readLines().filter { it.isNotBlank() } else emptyList()

    private fun idOf(raw: String): String? = runCatching { JSONObject(raw).getString("id") }.getOrNull()

    private fun file(context: Context, name: String) = File(context.filesDir, name)
}
