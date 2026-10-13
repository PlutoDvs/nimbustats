package com.nimbustats.app.widget

import java.security.SecureRandom
import java.util.Locale
import java.util.Random

/**
 * UUIDv7 ids for buffer lines (spec §2.1). A line's id becomes its row's id, and the app's own ids
 * are v7 too, so widget rows sort by time like every other row.
 *
 * Layout: 48 bits of Unix milliseconds, version 7, a 12-bit counter that keeps ids made in one
 * millisecond increasing, variant `10`, then 62 random bits. Pure: JUnit covers it.
 */
class Uuid7(
    private val clock: () -> Long = System::currentTimeMillis,
    private val random: Random = SecureRandom(),
) {
    private var lastMs = -1L
    private var counter = 0

    @Synchronized
    fun next(): String {
        var ms = clock()
        if (ms <= lastMs) {
            // The same millisecond, or a clock that stepped back: keep counting.
            ms = lastMs
            if (++counter > 0xFFF) {
                ms++ // borrow the next millisecond rather than repeat
                counter = random.nextInt(0x800)
            }
        } else {
            // Random, but in the lower half, so there is room to count up.
            counter = random.nextInt(0x800)
        }
        lastMs = ms
        val high = (ms shl 16) or (0x7L shl 12) or counter.toLong()
        val low = (random.nextLong() and 0x3FFF_FFFF_FFFF_FFFFL) or Long.MIN_VALUE
        val hex = String.format(Locale.ROOT, "%016x%016x", high, low)
        return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-" +
            "${hex.substring(16, 20)}-${hex.substring(20)}"
    }

    companion object {
        /** The process-wide generator every buffer append uses. */
        val shared = Uuid7()
    }
}
