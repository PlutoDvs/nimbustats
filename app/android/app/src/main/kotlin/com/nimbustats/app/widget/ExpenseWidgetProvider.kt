package com.nimbustats.app.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import com.nimbustats.app.notifications.ReminderScheduler

/**
 * The home-screen widget. Exported only for the system's widget broadcasts. Taps go to the
 * non-exported [WidgetActionReceiver] (ruling R9), so no other app can log a tap.
 */
class ExpenseWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        WidgetRenderer.renderAll(context)
        ReminderScheduler.armMidnight(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        WidgetRenderer.renderAll(context)
    }

    override fun onEnabled(context: Context) = ReminderScheduler.armMidnight(context)

    override fun onDisabled(context: Context) = ReminderScheduler.cancelMidnight(context)
}
