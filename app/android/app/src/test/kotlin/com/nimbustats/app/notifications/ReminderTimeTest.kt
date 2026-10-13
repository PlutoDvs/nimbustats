package com.nimbustats.app.notifications

import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class ReminderTimeTest {
    private val tehran = ZoneId.of("Asia/Tehran")
    private val newYork = ZoneId.of("America/New_York")
    private val nine = 21 * 60

    private fun at(zone: ZoneId, y: Int, mo: Int, d: Int, h: Int, mi: Int) =
        ZonedDateTime.of(y, mo, d, h, mi, 0, 0, zone)

    @Test
    fun laterTodayWhenTheTimeIsStillAhead() {
        assertEquals(
            at(tehran, 2026, 10, 12, 21, 0),
            ReminderTime.nextTrigger(at(tehran, 2026, 10, 12, 9, 30), nine),
        )
    }

    @Test
    fun tomorrowWhenTheTimeHasPassedOrIsNow() {
        assertEquals(
            at(tehran, 2026, 10, 13, 21, 0),
            ReminderTime.nextTrigger(at(tehran, 2026, 10, 12, 21, 30), nine),
        )
        // Strictly after now: a reminder firing at 21:00 arms tomorrow's.
        assertEquals(
            at(tehran, 2026, 10, 13, 21, 0),
            ReminderTime.nextTrigger(at(tehran, 2026, 10, 12, 21, 0), nine),
        )
    }

    @Test
    fun aTimeInTheSpringGapMovesLaterByTheGap() {
        // 2026-03-08 02:30 does not exist in New York: clocks jump 02:00 -> 03:00.
        val trigger = ReminderTime.nextTrigger(at(newYork, 2026, 3, 8, 0, 0), 2 * 60 + 30)
        assertEquals(3, trigger.hour)
        assertEquals(30, trigger.minute)
        assertEquals(ZoneOffset.ofHours(-4), trigger.offset)
    }

    @Test
    fun aTimeInTheAutumnOverlapTakesTheEarlierInstant() {
        // 2026-11-01 01:30 happens twice in New York; java.time keeps the earlier offset.
        val trigger = ReminderTime.nextTrigger(at(newYork, 2026, 11, 1, 0, 0), 90)
        assertEquals(ZoneOffset.ofHours(-4), trigger.offset)
        assertEquals(1, trigger.hour)
        assertEquals(30, trigger.minute)
    }

    @Test
    fun aTimeZoneChangeMovesTheInstantToTheNewLocalTime() {
        val instant = at(tehran, 2026, 10, 12, 9, 0).toInstant()
        val inTehran = ReminderTime.nextTrigger(instant.atZone(tehran), nine)
        val inNewYork = ReminderTime.nextTrigger(instant.atZone(newYork), nine)
        assertEquals(21, inNewYork.hour)
        assertEquals(newYork, inNewYork.zone)
        // Same wall time, different instants: the alarm must be re-armed on a zone change.
        assertNotEquals(inTehran.toInstant(), inNewYork.toInstant())
    }

    @Test
    fun nextMidnightIsTheStartOfTomorrowLocally() {
        assertEquals(
            at(tehran, 2026, 10, 13, 0, 0),
            ReminderTime.nextMidnight(at(tehran, 2026, 10, 12, 23, 59)),
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun aMinuteOutsideTheDayIsRefused() {
        ReminderTime.nextTrigger(at(tehran, 2026, 10, 12, 9, 0), 1440)
    }
}
