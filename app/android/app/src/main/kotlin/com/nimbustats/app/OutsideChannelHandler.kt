package com.nimbustats.app

import android.content.Context
import android.util.Log
import com.nimbustats.app.notifications.Notifier
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
                "takeLaunchRoute" -> result.success(takeLaunchRoute())
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            // Reaches Dart as a PlatformException, which Dart reports (spec §9).
            Log.e(TAG, "outside channel: ${call.method} failed", error)
            result.error("native-failure", error.message, null)
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
