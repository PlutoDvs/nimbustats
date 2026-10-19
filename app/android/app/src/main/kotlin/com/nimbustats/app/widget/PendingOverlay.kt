package com.nimbustats.app.widget

import java.time.Instant
import java.time.ZoneId

/** One tracker tap still waiting in the buffer. */
data class PendingTap(val trackerId: String, val atUtc: Long)

/**
 * What a widget row shows for today (spec §6.3). That is the snapshot's total if the snapshot is
 * from today, or nothing if not, plus every tap still in the buffer whose local day is today.
 *
 * It is optimistic, so a tap shows at once. The drain's commit then moves the tap from "pending"
 * into the snapshot in one step, so the number never changes twice. Pure: JUnit covers it.
 */
object PendingOverlay {
    fun todayValue(
        snapshotDayKey: Int,
        snapshotTotal: Double,
        perTap: Double,
        trackerId: String,
        pending: List<PendingTap>,
        zone: ZoneId,
        now: Instant,
    ): Double {
        val today = dayKey(now, zone)
        val base = if (snapshotDayKey == today) snapshotTotal else 0.0
        val taps = pending.count {
            it.trackerId == trackerId && dayKey(Instant.ofEpochMilli(it.atUtc), zone) == today
        }
        return base + taps * perTap
    }

    /**
     * A goal's progress over its own period: the snapshot's, plus today's pending taps at [step]
     * each. Null once the snapshot is from another day, since the period may have rolled over;
     * the row then shows today's value until the app rewrites the snapshot.
     */
    fun goalValue(
        snapshotDayKey: Int,
        snapshotCurrent: Double,
        step: Double,
        trackerId: String,
        pending: List<PendingTap>,
        zone: ZoneId,
        now: Instant,
    ): Double? = if (snapshotDayKey != dayKey(now, zone)) {
        null
    } else {
        todayValue(snapshotDayKey, snapshotCurrent, step, trackerId, pending, zone, now)
    }

    /** A boolean tracker is done once today holds anything. */
    fun isDone(type: String, value: Double): Boolean = type == "boolean" && value > 0.0

    /** The local Gregorian `yyyymmdd` [instant] falls on, like every `local_date_key`. */
    fun dayKey(instant: Instant, zone: ZoneId): Int {
        val date = instant.atZone(zone).toLocalDate()
        return date.year * 10_000 + date.monthValue * 100 + date.dayOfMonth
    }
}
