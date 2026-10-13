package com.nimbustats.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.nimbustats.app.notifications.Notifier
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** The route a notification tap launched the app with, until Dart takes it. */
    private var launchRoute: String? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchRoute = intent?.getStringExtra(Notifier.EXTRA_ROUTE)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OutsideChannelHandler.CHANNEL)
        channel.setMethodCallHandler(
            OutsideChannelHandler(
                applicationContext,
                takeLaunchRoute = { launchRoute.also { launchRoute = null } },
                requestPermission = ::requestNotificationPermission,
            ),
        )
        OutsideChannelHandler.appChannel = channel
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        OutsideChannelHandler.appChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** A notification tapped while the app runs (`singleTop`): Dart navigates. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val route = intent.getStringExtra(Notifier.EXTRA_ROUTE) ?: return
        OutsideChannelHandler.appChannel?.invokeMethod("openRoute", route)
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
        // A second ask while the dialog is up answers the first, so no Dart future waits forever.
        permissionResult?.success(false)
        permissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) return
        permissionResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        permissionResult = null
    }

    private companion object {
        const val REQUEST_NOTIFICATIONS = 6_100
    }
}
