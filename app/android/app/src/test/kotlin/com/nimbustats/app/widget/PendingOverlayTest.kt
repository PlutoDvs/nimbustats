package com.nimbustats.app.widget

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingOverlayTest {
    private val tehran = ZoneId.of("Asia/Tehran")
    private val noon = Instant.parse("2026-10-12T08:30:00Z") // 12:00 on the 12th in Tehran
    private fun tap(id: String, at: Instant = noon) = PendingTap(id, at.toEpochMilli())

    private fun value(dayKey: Int, total: Double, perTap: Double, pending: List<PendingTap>) =
        PendingOverlay.todayValue(dayKey, total, perTap, "cig", pending, tehran, noon)

    @Test
    fun todaysSnapshotPlusTodaysTapsForThisTracker() {
        assertEquals(5.0, value(20261012, 3.0, 1.0, listOf(tap("cig"), tap("cig"), tap("tea"))), 0.0)
    }

    @Test
    fun aSnapshotFromAnotherDayCountsAsNothing() {
        assertEquals(1.0, value(20261011, 7.0, 1.0, listOf(tap("cig"))), 0.0)
    }

    @Test
    fun aTapFromBeforeMidnightDoesNotCountToday() { // Review Focus 1
        val lateLastNight = Instant.parse("2026-10-11T20:29:00Z") // 23:59 on the 11th in Tehran
        assertEquals(0.0, value(20261012, 0.0, 1.0, listOf(tap("cig", lateLastNight))), 0.0)
    }

    @Test
    fun aQuantityTapAddsItsPerTapAmount() {
        assertEquals(1.0, value(20261012, 0.5, 0.25, listOf(tap("cig"), tap("cig"))), 1e-9)
    }

    private fun goal(dayKey: Int, current: Double, step: Double, pending: List<PendingTap>) =
        PendingOverlay.goalValue(dayKey, current, step, "cig", pending, tehran, noon)

    @Test
    fun aGoalAddsTodaysTapsByItsStepToTheSnapshotsProgress() {
        assertEquals(14.5, goal(20261012, 14.0, 0.25, listOf(tap("cig"), tap("cig"), tap("tea")))!!, 1e-9)
    }

    @Test
    fun aGoalFromAnotherDaysSnapshotIsNotShown() { // its period may have rolled over
        assertNull(goal(20261011, 14.0, 1.0, listOf(tap("cig"))))
    }

    @Test
    fun aBooleanIsDoneOnceTodayHoldsAnything() {
        assertTrue(PendingOverlay.isDone("boolean", 1.0))
        assertFalse(PendingOverlay.isDone("boolean", 0.0))
        assertFalse(PendingOverlay.isDone("counter", 3.0))
    }

    @Test
    fun theDayKeyIsTheLocalGregorianDate() {
        assertEquals(20261011, PendingOverlay.dayKey(Instant.parse("2026-10-11T20:29:00Z"), tehran))
        assertEquals(20261012, PendingOverlay.dayKey(Instant.parse("2026-10-11T20:31:00Z"), tehran))
    }
}
