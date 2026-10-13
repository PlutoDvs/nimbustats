package com.nimbustats.app.notifications

import java.time.Instant
import java.time.LocalTime
import java.time.ZonedDateTime

/**
 * When the daily reminder and the widget's midnight refresh fire next (spec §5, §6.3).
 *
 * Computed from the local wall clock every time, never as a fixed 24 hours, so daylight saving
 * and time-zone changes stay correct where `setInexactRepeating` drifts. A wall time inside a
 * DST gap or overlap resolves the way `java.time` resolves it: later by the gap, or the earlier
 * offset. Pure: no Android, so JUnit covers it on the host.
 */
object ReminderTime {
    /** The next local occurrence of [minuteOfDay] strictly after [now], in [now]'s zone. */
    fun nextTrigger(now: ZonedDateTime, minuteOfDay: Int): ZonedDateTime {
        require(minuteOfDay in 0 until 24 * 60) { "minuteOfDay $minuteOfDay is outside the day" }
        val time = LocalTime.of(minuteOfDay / 60, minuteOfDay % 60)
        val today = ZonedDateTime.of(now.toLocalDate(), time, now.zone)
        return if (today.isAfter(now)) today else ZonedDateTime.of(now.toLocalDate().plusDays(1), time, now.zone)
    }

    /**
     * When a re-arm should arm the reminder (spec §5). Android delivers the alarm inexactly, so a
     * re-arm — a clock sync, a zone or locale change, a boot, the app's own push — can land after
     * the armed time but before delivery. A trigger armed for today that is due and not yet
     * delivered ([pendingAt]) fires [now] instead of skipping to tomorrow; otherwise the next
     * occurrence strictly after [now].
     */
    fun rearmTrigger(now: ZonedDateTime, minuteOfDay: Int, pendingAt: Instant?): ZonedDateTime {
        val next = nextTrigger(now, minuteOfDay) // also validates minuteOfDay on the fire-now path
        val dueToday = pendingAt != null &&
            !pendingAt.isAfter(now.toInstant()) &&
            pendingAt.atZone(now.zone).toLocalDate() == now.toLocalDate()
        return if (dueToday) now else next
    }

    /** The start of tomorrow, locally. */
    fun nextMidnight(now: ZonedDateTime): ZonedDateTime = now.toLocalDate().plusDays(1).atStartOfDay(now.zone)
}
