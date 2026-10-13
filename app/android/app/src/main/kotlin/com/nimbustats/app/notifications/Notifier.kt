package com.nimbustats.app.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.util.Log
import com.nimbustats.app.MainActivity
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import com.nimbustats.app.R

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
                NotificationChannel(ALERTS, alertsName, NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = alertsDescription
                    // Spec §4.3: the lock screen always gets the public version, even when the
                    // user's global setting shows all content. Android fixes it at first creation.
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                },
                NotificationChannel(REMINDER, reminderName, NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = reminderDescription },
            ),
        )
    }

    /**
     * A goal alert (spec §4.3). Tag `goal:<id>` and id 1, so a 100% crossing replaces that goal's
     * 80% one. The lock screen shows [publicText], never a name or an amount.
     *
     * A post Android would drop is logged instead: the crossing is already recorded, so it is
     * not retried (spec §9).
     */
    fun postAlert(context: Context, tag: String, text: String, publicText: String, route: String) {
        if (!canPost(context, ALERTS, "goal alert $tag")) return
        val public = Notification.Builder(context, ALERTS)
            .setSmallIcon(R.drawable.ic_stat_nimbus)
            .setContentText(publicText)
            .build()
        val notification = Notification.Builder(context, ALERTS)
            .setSmallIcon(R.drawable.ic_stat_nimbus)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(public)
            .setContentIntent(routeIntent(context, route, tag))
            .setAutoCancel(true)
            .build()
        context.getSystemService(NotificationManager::class.java).notify(tag, 1, notification)
    }

    /** The daily reminder (spec §5). A tap opens [route]: the add-expense screen. */
    fun postReminder(context: Context, text: String, route: String) {
        if (!canPost(context, REMINDER, "reminder")) return
        val notification = Notification.Builder(context, REMINDER)
            .setSmallIcon(R.drawable.ic_stat_nimbus)
            .setContentText(text)
            .setContentIntent(routeIntent(context, route, "reminder"))
            .setAutoCancel(true)
            .build()
        context.getSystemService(NotificationManager::class.java).notify("reminder", 1, notification)
    }

    /** Opens [route] in the app: `MainActivity` passes it to Dart (launch or `openRoute`). */
    internal fun routeIntent(context: Context, route: String, key: String): PendingIntent =
        PendingIntent.getActivity(
            context,
            key.hashCode(),
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_ROUTE, route)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    /** Whether a post on [channel] would be shown; if not, says why in logcat. */
    internal fun canPost(context: Context, channel: String, what: String): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        val reason = when {
            !manager.areNotificationsEnabled() -> "notifications are disabled"
            manager.getNotificationChannel(channel) == null -> "channel $channel is not registered yet"
            manager.getNotificationChannel(channel).importance == NotificationManager.IMPORTANCE_NONE ->
                "channel $channel is blocked"
            else -> return true
        }
        Log.e(TAG, "$what not shown: $reason")
        return false
    }

    fun settingsIntent(context: Context): Intent =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
