package com.nimbustats.app.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import com.nimbustats.app.notifications.ReminderScheduler

/**
 * The home-screen widget. Exported only for the system's widget broadcasts. Taps go to the
 * non-exported [WidgetActionReceiver] (ruling R9), so no other app can log a tap.
 */
class ExpenseWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        // A render failure must not skip arming the midnight refresh.
        try {
            WidgetRenderer.renderAll(context)
        } catch (error: Exception) {
            Log.e(TAG, "widget render failed on update", error)
        }
        ReminderScheduler.armMidnight(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        // A resize is a system broadcast: anything escaping here would crash the app's process.
        try {
            WidgetRenderer.renderAll(context)
        } catch (error: Exception) {
            Log.e(TAG, "widget render failed on resize", error)
        }
    }

    override fun onEnabled(context: Context) = ReminderScheduler.armMidnight(context)

    override fun onDisabled(context: Context) = ReminderScheduler.cancelMidnight(context)
}
