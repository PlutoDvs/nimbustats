package com.nimbustats.app.backup

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.FileProvider
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

/**
 * The native half of `com.nimbustats.app/backup` (Phase 7 spec §6).
 *
 * Save goes through the Storage Access Framework, and Share through the share sheet. Open copies
 * the picked file into the cache, where Dart reads it. The Dart flow is modal, so one picker
 * waits at a time. Every I/O failure reaches Dart as an error reply.
 */
class BackupDocuments(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private class Waiting(val request: Int, val result: MethodChannel.Result, val source: File?)

    private var waiting: Waiting? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveDocument" -> save(File(call.argument<String>("path")!!), result)
            "shareFile" -> share(File(call.argument<String>("path")!!), result)
            "openDocument" -> open(result)
            else -> result.notImplemented()
        }
    }

    private fun save(source: File, result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(MIME)
            .putExtra(Intent.EXTRA_TITLE, source.name)
        start(Waiting(REQUEST_SAVE, result, source), intent)
    }

    private fun share(file: File, result: MethodChannel.Result) {
        // backup_file_paths.xml serves cache/backup/out/ only. Any other path throws here, and
        // the channel returns that to Dart as an error.
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.backup", file)
        val send = Intent(Intent.ACTION_SEND)
            .setType(MIME)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        // The chooser passes the read grant on only through ClipData.
        send.clipData = ClipData.newRawUri(file.name, uri)
        activity.startActivity(Intent.createChooser(send, null))
        result.success(null)
    }

    private fun open(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
        start(Waiting(REQUEST_OPEN, result, null), intent)
    }

    private fun start(next: Waiting, intent: Intent) {
        if (waiting != null) {
            next.result.error("busy", "a backup picker is already open", null)
            return
        }
        waiting = next
        activity.startActivityForResult(intent, next.request)
    }

    /** MainActivity hands over every activity result. True when it was one of ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val done = waiting?.takeIf { it.request == requestCode } ?: return false
        waiting = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // A cancelled picker is not an error (spec §5.2).
            done.result.success(if (requestCode == REQUEST_SAVE) false else null)
            return true
        }
        io.execute {
            try {
                val reply: Any = if (requestCode == REQUEST_SAVE) {
                    copyOut(done.source!!, uri)
                    true
                } else {
                    copyIn(uri)
                }
                main.post { done.result.success(reply) }
            } catch (error: Exception) {
                Log.e(TAG, "backup document copy failed", error)
                main.post { done.result.error("io", error.javaClass.simpleName, null) }
            }
        }
        return true
    }

    private fun copyOut(source: File, target: Uri) {
        // "wt" truncates, so saving over a longer old file leaves no tail of it.
        val out = activity.contentResolver.openOutputStream(target, "wt")
            ?: throw IOException("no output stream")
        out.use { stream -> source.inputStream().use { it.copyTo(stream) } }
    }

    private fun copyIn(source: Uri): String {
        val dir = File(activity.cacheDir, "backup").apply { mkdirs() }
        val target = File(dir, "picked-${UUID.randomUUID()}.nimbus")
        val input = activity.contentResolver.openInputStream(source)
            ?: throw IOException("no input stream")
        input.use { stream -> target.outputStream().use { stream.copyTo(it) } }
        return target.path
    }

    companion object {
        const val CHANNEL = "com.nimbustats.app/backup"
        private const val MIME = "application/octet-stream"
        private const val REQUEST_SAVE = 7_100
        private const val REQUEST_OPEN = 7_101
    }
}
