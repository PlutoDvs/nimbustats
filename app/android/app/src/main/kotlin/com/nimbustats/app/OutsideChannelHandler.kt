package com.nimbustats.app

import android.content.Context
import android.util.Log
import com.nimbustats.app.notifications.Notifier
import com.nimbustats.app.notifications.ReminderScheduler
import com.nimbustats.app.widget.WidgetBuffer
import com.nimbustats.app.widget.WidgetRenderer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Answers Dart on the `com.nimbustats.app/outside` channel (spec §1.1) for both engines.
 *
 * - The app's engine registers it in [MainActivity], with the launch route and the permission
 *   dialog.
 * - The widget drain's headless engine registers it in `DrainJobService`, with
 *   [onDrainFinished].
 *
 * Native code stores and displays; every string arrives from Dart.
 */
class OutsideChannelHandler(
    private val context: Context,
    private val takeLaunchRoute: () -> String? = { null },
    private val requestPermission: ((MethodChannel.Result) -> Unit)? = null,
    private val onDrainFinished: ((Boolean) -> Unit)? = null,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "notificationsEnabled" -> result.success(Notifier.enabled(context))
                "requestNotificationPermission" -> {
                    val request = requestPermission
                    if (request == null) {
                        result.error("no-activity", "the permission dialog needs the app's activity", null)
                    } else {
                        request(result)
                    }
                }
                "openNotificationSettings" -> {
                    context.startActivity(Notifier.settingsIntent(context))
                    result.success(null)
                }
                "registerChannels" -> {
                    Notifier.registerChannels(
                        context,
                        call.string("alertsName"),
                        call.string("alertsDescription"),
                        call.string("reminderName"),
                        call.string("reminderDescription"),
                    )
                    result.success(null)
                }
                "postAlert" -> {
                    Notifier.postAlert(
                        context,
                        call.string("tag"),
                        call.string("text"),
                        call.string("publicText"),
                        call.string("route"),
                    )
                    result.success(null)
                }
                "setReminder" -> {
                    ReminderScheduler.configure(
                        context,
                        call.argument<Boolean>("enabled") ?: throw IllegalArgumentException("missing enabled"),
                        call.argument<Int>("minuteOfDay") ?: throw IllegalArgumentException("missing minuteOfDay"),
                        call.string("text"),
                        call.string("route"),
                    )
                    result.success(null)
                }
                "takeBuffer" -> result.success(WidgetBuffer.lines(context))
                "writeSnapshot" -> {
                    WidgetBuffer.writeSnapshot(context, call.string("snapshot"))
                    renderWidget()
                    result.success(null)
                }
                "commitDrain" -> {
                    val ackIds = call.argument<List<String>>("ackIds")
                        ?: throw IllegalArgumentException("missing ackIds")
                    val rejected = call.argument<List<Map<String, String>>>("rejected")
                        ?: throw IllegalArgumentException("missing rejected")
                    WidgetBuffer.commit(
                        context,
                        call.string("snapshot"),
                        ackIds.toSet(),
                        rejected.associate {
                            (it["line"] ?: throw IllegalArgumentException("rejected without line")) to
                                (it["reason"] ?: throw IllegalArgumentException("rejected without reason"))
                        },
                    )
                    renderWidget()
                    result.success(null)
                }
                "drainFinished" -> {
                    val done = onDrainFinished
                        ?: throw IllegalStateException("drainFinished outside the headless drain engine")
                    val ok = call.argument<Boolean>("ok") ?: throw IllegalArgumentException("missing ok")
                    result.success(null)
                    done(ok)
                }
                "takeLaunchRoute" ->result.success(takeLaunchRoute())
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            // Reaches Dart as a PlatformException, which Dart reports (spec §9).
            Log.e(TAG, "outside channel: ${call.method} failed", error)
            result.error("native-failure", error.message, null)
        }
    }

    /** A render failure must not make the channel report a written snapshot or a committed drain as failed. */
    private fun renderWidget() {
        try {
            WidgetRenderer.renderAll(context)
        } catch (error: RuntimeException) {
            Log.e(TAG, "widget render failed after the write", error)
        }
    }

    companion object {
        const val CHANNEL = "com.nimbustats.app/outside"
        const val TAG = "NimbuStats"

        /**
         * The app engine's channel while its activity lives. The drain job hands the app engine
         * the work through it (spec §2.4).
         */
        @Volatile
        var appChannel: MethodChannel? = null
    }
}

/** A required string argument. A missing one is Dart's bug, so it fails loudly. */
internal fun MethodCall.string(key: String): String =
    argument<String>(key) ?: throw IllegalArgumentException("missing argument $key")
