package com.nimbustats.app.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class Uuid7Test {
    private val shape = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")

    @Test
    fun versionSevenAndVariantTen() {
        val generator = Uuid7()
        repeat(200) { assertTrue(shape.matches(generator.next())) }
    }

    @Test
    fun theFirst48BitsAreTheMillisecond() {
        val id = Uuid7(clock = { 0x01933F2A1B2CL }).next()
        assertEquals("01933f2a-1b2c", id.substring(0, 13))
    }

    @Test
    fun idsMadeInOneMillisecondKeepIncreasing() {
        // More than the 12-bit counter holds, so the borrow path runs too.
        val generator = Uuid7(clock = { 1_760_270_000_000L })
        val ids = List(5_000) { generator.next() }
        assertEquals(ids.sorted(), ids)
        assertEquals(ids.size, ids.toSet().size)
    }

    @Test
    fun aClockGoingBackDoesNotGoBack() {
        var now = 2_000_000L
        val generator = Uuid7(clock = { now })
        val first = generator.next()
        now = 1_000_000L
        assertTrue(generator.next() > first)
    }
}
