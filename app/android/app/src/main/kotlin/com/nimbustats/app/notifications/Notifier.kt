package com.nimbustats.app.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.provider.Settings

/**
 * The app's two notification channels (spec §4.1) and the posts made on them.
 *
 * Every text it shows arrives from Dart in the app's language; nothing here composes one.
 */
object Notifier {
    const val ALERTS = "alerts"
    const val REMINDER = "reminder"

    /** The route a notification tap opens, carried to [com.nimbustats.app.MainActivity]. */
    const val EXTRA_ROUTE = "com.nimbustats.app.ROUTE"

    fun enabled(context: Context): Boolean =
        context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    /**
     * Creates both channels, or renames them: creating an existing id again updates its name
     * and description, which is how a language switch reaches Android's settings.
     */
    fun registerChannels(
        context: Context,
        alertsName: String,
        alertsDescription: String,
        reminderName: String,
        reminderDescription: String,
    ) {
        context.getSystemService(NotificationManager::class.java).createNotificationChannels(
            listOf(
                NotificationChannel(ALERTS, alertsName, NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = alertsDescription },
                NotificationChannel(REMINDER, reminderName, NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = reminderDescription },
            ),
        )
    }

    fun settingsIntent(context: Context): Intent =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
