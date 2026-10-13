package com.nimbustats.app.notifications

import java.time.Instant
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

    @Test
    fun aRearmWithNothingPendingArmsTheNextOccurrence() {
        val now = at(tehran, 2026, 10, 13, 9, 30)
        assertEquals(ReminderTime.nextTrigger(now, nine), ReminderTime.rearmTrigger(now, nine, null))
    }

    @Test
    fun aRearmAfterTheArmedTimeButBeforeDeliveryFiresNow() {
        // The A53: armed for 22:46, a network clock sync at 22:48:59 re-armed before delivery.
        val now = ZonedDateTime.of(2026, 10, 13, 22, 48, 59, 0, tehran)
        val pending = at(tehran, 2026, 10, 13, 22, 46).toInstant()
        assertEquals(now, ReminderTime.rearmTrigger(now, 22 * 60 + 46, pending))
    }

    @Test
    fun aPendingTriggerFromAnEarlierDayIsNotFiredNow() {
        val yesterdays = at(tehran, 2026, 10, 12, 21, 0).toInstant()
        val morning = at(tehran, 2026, 10, 13, 9, 30)
        assertEquals(at(tehran, 2026, 10, 13, 21, 0), ReminderTime.rearmTrigger(morning, nine, yesterdays))
        val evening = at(tehran, 2026, 10, 13, 21, 30)
        assertEquals(at(tehran, 2026, 10, 14, 21, 0), ReminderTime.rearmTrigger(evening, nine, yesterdays))
    }

    @Test
    fun aPendingTriggerStillAheadIsTheNextOccurrence() {
        val now = at(tehran, 2026, 10, 13, 9, 30)
        val pending = at(tehran, 2026, 10, 13, 21, 0)
        assertEquals(pending, ReminderTime.rearmTrigger(now, nine, pending.toInstant()))
    }

    @Test
    fun aPendingTriggerExactlyNowFiresNow() {
        val now = at(tehran, 2026, 10, 13, 21, 0)
        assertEquals(now, ReminderTime.rearmTrigger(now, nine, now.toInstant()))
    }

    @Test
    fun aZoneChangeKeepsAnOverduePendingTriggerThatIsStillToday() {
        // Armed for 21:00 Tehran = 13:30 in New York; at 14:00 there it is overdue and still today.
        val pending = at(tehran, 2026, 10, 13, 21, 0).toInstant()
        val now = at(newYork, 2026, 10, 13, 14, 0)
        assertEquals(now, ReminderTime.rearmTrigger(now, nine, pending))
    }

    @Test(expected = IllegalArgumentException::class)
    fun aRearmWithAMinuteOutsideTheDayIsRefused() {
        val now = at(tehran, 2026, 10, 13, 22, 0)
        ReminderTime.rearmTrigger(now, 1440, now.toInstant())
    }
}
