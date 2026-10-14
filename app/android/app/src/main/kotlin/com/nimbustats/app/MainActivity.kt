package com.nimbustats.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import com.nimbustats.app.notifications.Notifier
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** The route a notification tap launched the app with, until Dart takes it. */
    private var launchRoute: String? = null

    /** This activity's channel to its engine; null while it has none. */
    private var channel: MethodChannel? = null

    /** Every Dart ask waiting on the one permission dialog. */
    private val permissionResults = mutableListOf<MethodChannel.Result>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchRoute = takeRoute(intent)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OutsideChannelHandler.CHANNEL)
        channel.setMethodCallHandler(
            OutsideChannelHandler(
                applicationContext,
                takeLaunchRoute = { launchRoute.also { launchRoute = null } },
                requestPermission = ::requestNotificationPermission,
            ),
        )
        this.channel = channel
        OutsideChannelHandler.appChannel = channel
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel = null
        OutsideChannelHandler.appChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** A notification tapped while the app runs (`singleTop`): Dart navigates. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val route = takeRoute(intent) ?: return
        val channel = channel ?: run {
            launchRoute = route
            return
        }
        channel.invokeMethod(
            "openRoute",
            route,
            object : MethodChannel.Result {
                override fun success(result: Any?) = Unit

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e(TAG, "openRoute $route failed: $errorCode $errorMessage")
                }

                // Dart's bridge is not mounted yet; it takes the launch route when it mounts.
                override fun notImplemented() {
                    launchRoute = route
                }
            },
        )
    }

    /**
     * The route a notification put on [intent], read once. A launch from Recents replays the
     * notification's intent, so it carries none.
     */
    private fun takeRoute(intent: Intent?): String? {
        if (intent == null || (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return null
        return intent.getStringExtra(Notifier.EXTRA_ROUTE).also { intent.removeExtra(Notifier.EXTRA_ROUTE) }
    }

    /**
     * Spec §4.2. Below Android 13, or when already granted, it answers at once with no dialog.
     * After two denials Android shows nothing and answers false. No "already asked" state is kept.
     */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(Notifier.enabled(this))
            return
        }
        // One dialog answers every ask made while it is up: a second request would be answered at
        // once with empty arrays. Queued before the request, so an answer Android gives at once
        // (a cancel while another request is in flight) still reaches it, as false (D27).
        permissionResults += result
        if (permissionResults.size > 1) return
        try {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        } catch (error: Exception) {
            // Not left waiting: the channel answers it with this error instead.
            permissionResults.remove(result)
            throw error
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        val waiting = permissionResults.toList()
        permissionResults.clear()
        waiting.forEach { it.success(granted) }
    }

    private companion object {
        const val REQUEST_NOTIFICATIONS = 6_100
    }
}
