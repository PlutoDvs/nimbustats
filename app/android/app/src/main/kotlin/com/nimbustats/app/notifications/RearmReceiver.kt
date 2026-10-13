package com.nimbustats.app.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms after the events that silently clear or move an alarm: a reboot, a time-zone change, a
 * clock change, a locale change and an app update (spec §5). Each is a protected broadcast only
 * the system sends, and each is on Android's implicit-broadcast exemption list.
 */
class RearmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderScheduler.rearm(context)
    }
}
