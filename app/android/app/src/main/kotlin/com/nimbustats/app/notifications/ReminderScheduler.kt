package com.nimbustats.app.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.time.ZonedDateTime

/**
 * Arms the daily reminder (spec §5).
 *
 * It keeps Dart's last config in SharedPreferences, so [RearmReceiver] can re-arm after a reboot
 * or a zone change without starting Flutter. The alarm is `setAndAllowWhileIdle(RTC_WAKEUP)`:
 * inexact, delivered in Doze, needing no exact-alarm permission. It is one-shot, and each firing
 * arms the next.
 */
object ReminderScheduler {
    private const val PREFS = "nimbus_reminder"
    private const val ENABLED = "enabled"
    private const val MINUTE = "minuteOfDay"
    private const val TEXT = "text"
    private const val ROUTE = "route"

    fun configure(context: Context, enabled: Boolean, minuteOfDay: Int, text: String, route: String) {
        require(minuteOfDay in 0 until 24 * 60) { "minuteOfDay $minuteOfDay is outside the day" }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(ENABLED, enabled)
            .putInt(MINUTE, minuteOfDay)
            .putString(TEXT, text)
            .putString(ROUTE, route)
            .apply()
        armReminder(context)
    }

    /** Everything this app keeps armed, re-armed from the local clock now. */
    fun rearm(context: Context) {
        armReminder(context)
    }

    fun armReminder(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val intent = reminderIntent(context)
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(ENABLED, false)) {
            alarms.cancel(intent)
            return
        }
        val at = ReminderTime.nextTrigger(ZonedDateTime.now(), prefs.getInt(MINUTE, 21 * 60))
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.toInstant().toEpochMilli(), intent)
    }

    /** The stored text and route, or null when Dart never configured the reminder. */
    fun content(context: Context): Pair<String, String>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val text = prefs.getString(TEXT, null) ?: return null
        val route = prefs.getString(ROUTE, null) ?: return null
        return text to route
    }

    private fun reminderIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, ReminderReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}
