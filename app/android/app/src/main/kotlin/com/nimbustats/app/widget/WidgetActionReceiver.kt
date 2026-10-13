package com.nimbustats.app.widget

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import com.nimbustats.app.notifications.ReminderScheduler

/**
 * The widget's own actions. It is not exported: only this app's PendingIntents reach it.
 * - **A tracker tap** appends one buffer line, re-renders with the tap counted, and enqueues the
 *   drain. Nothing waits for Flutter.
 * - **Local midnight** re-renders, so yesterday's totals clear, and arms the next midnight.
 */
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TAP -> {
                val trackerId = intent.getStringExtra(EXTRA_TRACKER)
                if (trackerId == null) {
                    Log.e(TAG, "widget tap without a tracker id; nothing logged")
                    return
                }
                WidgetBuffer.appendTrackerTap(context, System.currentTimeMillis(), trackerId)
                WidgetRenderer.renderAll(context)
                DrainScheduler.enqueue(context)
            }
            ACTION_MIDNIGHT -> {
                WidgetRenderer.renderAll(context)
                ReminderScheduler.armMidnight(context)
            }
            else -> Log.e(TAG, "unknown widget action ${intent.action}")
        }
    }

    companion object {
        private const val ACTION_TAP = "com.nimbustats.app.widget.TAP"
        private const val ACTION_MIDNIGHT = "com.nimbustats.app.widget.MIDNIGHT"
        private const val EXTRA_TRACKER = "trackerId"

        /** One intent per tracker. The data URI keeps them distinct, so each row logs its own tracker. */
        fun tapIntent(context: Context, trackerId: String): PendingIntent = PendingIntent.getBroadcast(
            context,
            trackerId.hashCode(),
            Intent(context, WidgetActionReceiver::class.java)
                .setAction(ACTION_TAP)
                .setData(Uri.parse("nimbustats://tracker/$trackerId"))
                .putExtra(EXTRA_TRACKER, trackerId),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        fun midnightIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, WidgetActionReceiver::class.java).setAction(ACTION_MIDNIGHT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
