package com.nimbustats.app.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG

/**
 * The reminder's alarm: arms tomorrow's from the local clock, then posts (spec §5).
 *
 * Arming comes first because the alarm is one-shot: a failed post must not end the chain. This IS
 * the delivery, so it arms with `afterFiring`: the just-fired trigger is not pending, and the next
 * one is strictly after now, so this slot cannot re-fire.
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderScheduler.armReminder(context, afterFiring = true)
        try {
            val content = ReminderScheduler.content(context)
            if (content == null) {
                Log.e(TAG, "reminder fired with no text stored; nothing posted")
            } else {
                Notifier.postReminder(context, content.first, content.second)
            }
        } catch (e: Exception) {
            // A receiver has no caller to report to (spec §9): log, do not crash.
            Log.e(TAG, "posting the daily reminder failed", e)
        }
    }
}
