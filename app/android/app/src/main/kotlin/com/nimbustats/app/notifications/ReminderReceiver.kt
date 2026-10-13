package com.nimbustats.app.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG

/** The reminder's alarm: posts it, then arms tomorrow's from the local clock (spec §5). */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val content = ReminderScheduler.content(context)
        if (content == null) {
            Log.e(TAG, "reminder fired with no text stored; nothing posted")
        } else {
            Notifier.postReminder(context, content.first, content.second)
        }
        ReminderScheduler.armReminder(context)
    }
}
