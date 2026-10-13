package com.nimbustats.app.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import com.nimbustats.app.widget.WidgetRenderer

/**
 * Re-arms after the events that silently clear or move an alarm: a reboot, a time-zone change, a
 * clock change, a locale change and an app update (spec §5). Each is a protected broadcast only
 * the system sends, and each is on Android's implicit-broadcast exemption list.
 */
class RearmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderScheduler.rearm(context)
        // A zone or clock change can move today; re-render so the rows follow it.
        try {
            WidgetRenderer.renderAll(context)
        } catch (error: Exception) {
            Log.e(TAG, "widget render failed after a re-arm", error)
        }
    }
}
