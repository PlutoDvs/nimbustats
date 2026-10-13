package com.nimbustats.app.notifications

import android.app.AlarmManager
import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import com.nimbustats.app.widget.ExpenseWidgetProvider
import com.nimbustats.app.widget.WidgetActionReceiver
import java.time.Instant
import java.time.ZonedDateTime

/**
 * Arms the daily reminder (spec §5).
 *
 * It keeps Dart's last config in SharedPreferences, so [RearmReceiver] can re-arm after a reboot
 * or a zone change without starting Flutter. The alarm is `setAndAllowWhileIdle(RTC_WAKEUP)`:
 * inexact, delivered in Doze, needing no exact-alarm permission. It is one-shot, and each firing
 * arms the next. It also keeps the trigger it armed last (`armedAt`, epoch ms): a re-arm that
 * lands after that time but before Android delivers it fires now instead of skipping the day
 * ([ReminderTime.rearmTrigger]).
 */
object ReminderScheduler {
    private const val PREFS = "nimbus_reminder"
    private const val ENABLED = "enabled"
    private const val MINUTE = "minuteOfDay"
    private const val TEXT = "text"
    private const val ROUTE = "route"
    private const val ARMED_AT = "armedAt"

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
        armMidnight(context)
    }

    /**
     * Arms the reminder, or cancels it when disabled. [afterFiring] is the receiver's own arm: the
     * trigger it was armed for has just been delivered, so it arms the next occurrence; every
     * other caller is a re-arm and keeps an overdue, undelivered `armedAt` from today.
     */
    fun armReminder(context: Context, afterFiring: Boolean = false) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val intent = reminderIntent(context)
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(ENABLED, false)) {
            alarms.cancel(intent)
            prefs.edit().remove(ARMED_AT).apply()
            return
        }
        val now = ZonedDateTime.now()
        val minute = prefs.getInt(MINUTE, 21 * 60)
        val at = if (afterFiring) {
            ReminderTime.nextTrigger(now, minute)
        } else {
            val armedAt = if (prefs.contains(ARMED_AT)) prefs.getLong(ARMED_AT, 0) else null
            ReminderTime.rearmTrigger(now, minute, armedAt?.let(Instant::ofEpochMilli))
        }
        val atMillis = at.toInstant().toEpochMilli()
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, intent)
        prefs.edit().putLong(ARMED_AT, atMillis).apply()
    }

    /**
     * The widget's local-midnight refresh (spec §6.3). It uses inexact, non-waking `RTC`: a
     * sleeping phone shows the widget at its next wake, and yesterday's totals clear then. It is
     * armed only while a widget is placed.
     */
    fun armMidnight(context: Context) {
        val widgets = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, ExpenseWidgetProvider::class.java))
        if (widgets.isEmpty()) {
            cancelMidnight(context)
            return
        }
        context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(
            AlarmManager.RTC,
            ReminderTime.nextMidnight(ZonedDateTime.now()).toInstant().toEpochMilli(),
            WidgetActionReceiver.midnightIntent(context),
        )
    }

    fun cancelMidnight(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(WidgetActionReceiver.midnightIntent(context))
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
