package com.nimbustats.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.icu.text.NumberFormat
import android.icu.util.ULocale
import android.os.Build
import android.util.Log
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import com.nimbustats.app.MainActivity
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import com.nimbustats.app.R
import java.time.Instant
import java.time.ZoneId

/**
 * Builds the widget from the snapshot plus the pending taps (spec §6.3–§6.5).
 *
 * | State     | When                                     | Shows                                    |
 * |-----------|------------------------------------------|------------------------------------------|
 * | loading   | no snapshot yet                          | the app icon; a tap opens the app        |
 * | error     | snapshot unreadable                      | as loading, plus a logged cause          |
 * | empty     | no eligible trackers                     | "+ Expense" and the empty-trackers text  |
 * | populated | otherwise                                | "+ Expense" and one row per tracker      |
 *
 * Android 12+ gets responsive layouts with 1 to 4 rows by height; below 12 there are 2 rows.
 * Numbers are formatted by ICU for the snapshot's language, with at most two fraction digits.
 * That is the CLDR data the app's `NumberFormat.decimalPattern` is built on (spec §6.2).
 */
object WidgetRenderer {
    private class Row(val tracker: SnapTracker, val value: String, val done: Boolean, val description: String)

    fun renderAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, ExpenseWidgetProvider::class.java))
        if (ids.isEmpty()) return
        val views = build(context)
        for (id in ids) manager.updateAppWidget(id, views)
    }

    private fun build(context: Context): RemoteViews {
        // One lock hold for both reads (P18): a commit cannot land between them, so a tap is
        // never counted twice (new snapshot + still pending) or not at all. Views are built outside.
        val (snapshot, pending) = synchronized(WidgetBuffer) {
            WidgetSnapshot.read(context) to WidgetBuffer.pendingTaps(context)
        }
        if (snapshot == null) return loading(context)
        return try {
            val rows = rows(snapshot, pending)
            if (Build.VERSION.SDK_INT >= 31) {
                RemoteViews(
                    mapOf(
                        SizeF(180f, 100f) to layout(context, snapshot, rows, 1),
                        SizeF(180f, 150f) to layout(context, snapshot, rows, 2),
                        SizeF(180f, 200f) to layout(context, snapshot, rows, 3),
                        SizeF(180f, 250f) to layout(context, snapshot, rows, 4),
                    ),
                )
            } else {
                layout(context, snapshot, rows, 2)
            }
        } catch (error: Exception) {
            Log.e(TAG, "widget render failed; showing the loading state", error)
            loading(context)
        }
    }

    private fun rows(snapshot: WidgetSnapshot, pending: List<PendingTap>): List<Row> {
        val format = NumberFormat.getInstance(ULocale.forLanguageTag(snapshot.localeTag)).apply {
            maximumFractionDigits = 2
        }
        val zone = ZoneId.systemDefault()
        val now = Instant.now()
        return snapshot.trackers.map { tracker ->
            val value = PendingOverlay.todayValue(
                snapshot.dayKey, tracker.todayTotal, tracker.perTap, tracker.id, pending, zone, now,
            )
            val done = PendingOverlay.isDone(tracker.type, value)
            // As TrackerFormat.total writes it: a quantity carries its unit.
            val text = tracker.unit?.let { "${format.format(value)} $it" } ?: format.format(value)
            val description = if (done) {
                snapshot.string("trackerDone").replace("{name}", tracker.name)
            } else {
                snapshot.string("trackerAdd").replace("{name}", tracker.name).replace("{total}", text)
            }
            Row(tracker, text, done, description)
        }
    }

    private fun layout(context: Context, snapshot: WidgetSnapshot, rows: List<Row>, capacity: Int): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_expense).apply {
            setInt(
                R.id.widget_root,
                "setLayoutDirection",
                if (snapshot.rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR,
            )
            setTextViewText(R.id.widget_add_expense, snapshot.string("addExpense"))
            setOnClickPendingIntent(R.id.widget_add_expense, entryIntent(context))
            removeAllViews(R.id.widget_rows)
            if (rows.isEmpty()) {
                setViewVisibility(R.id.widget_empty, View.VISIBLE)
                setTextViewText(R.id.widget_empty, snapshot.string("emptyTrackers"))
            } else {
                setViewVisibility(R.id.widget_empty, View.GONE)
                for (row in rows.take(capacity)) addView(R.id.widget_rows, rowViews(context, row))
            }
        }

    private fun rowViews(context: Context, row: Row): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_tracker_row).apply {
            setInt(R.id.row_dot, "setColorFilter", row.tracker.color)
            setTextViewText(R.id.row_name, row.tracker.name)
            // A boolean says it with the tick, not a number.
            setViewVisibility(R.id.row_value, if (row.tracker.type == "boolean") View.GONE else View.VISIBLE)
            setTextViewText(R.id.row_value, row.value)
            if (row.done) {
                setViewVisibility(R.id.row_add, View.GONE)
                setViewVisibility(R.id.row_done, View.VISIBLE)
                setContentDescription(R.id.row_done, row.description)
            } else {
                setViewVisibility(R.id.row_done, View.GONE)
                setViewVisibility(R.id.row_add, View.VISIBLE)
                setContentDescription(R.id.row_add, row.description)
                setOnClickPendingIntent(R.id.row_add, WidgetActionReceiver.tapIntent(context, row.tracker.id))
            }
        }

    private fun loading(context: Context): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_loading).apply {
            setOnClickPendingIntent(
                R.id.widget_loading_root,
                PendingIntent.getActivity(
                    context,
                    0,
                    Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }

    private fun entryIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        1,
        Intent(context, ExpenseEntryActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE,
    )
}
