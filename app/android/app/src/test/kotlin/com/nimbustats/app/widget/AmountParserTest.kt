package com.nimbustats.app.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AmountParserTest {
    @Test
    fun latinPersianAndArabicIndicDigitsReadTheSame() {
        assertEquals(12_500L, AmountParser.parse("12500", 0))
        assertEquals(12_500L, AmountParser.parse("۱۲۵۰۰", 0))
        assertEquals(12_500L, AmountParser.parse("١٢٥٠٠", 0))
    }

    @Test
    fun bothGroupSeparatorsAndSpacesAreIgnored() {
        assertEquals(12_500L, AmountParser.parse("12,500", 0))
        assertEquals(12_500L, AmountParser.parse("۱۲٬۵۰۰", 0)) // Review Focus 2
        assertEquals(12_500L, AmountParser.parse(" 12 500 ", 0))
        assertEquals(12_500L, AmountParser.parse("12 500", 0))
    }

    @Test
    fun fractionsFollowTheCurrency() {
        assertEquals(1_250L, AmountParser.parse("12.5", 2))
        assertEquals(1_205L, AmountParser.parse("12.05", 2))
        assertEquals(1_200L, AmountParser.parse("12.", 2))
        assertEquals(50L, AmountParser.parse(".5", 2))
        assertNull(AmountParser.parse("12.345", 2))
        assertNull(AmountParser.parse("12.5", 0)) // Toman has no fraction
        assertEquals(12L, AmountParser.parse("12.", 0))
    }

    @Test
    fun zeroAndNegativeCannotBeSaved() {
        assertNull(AmountParser.parse("0", 0))
        assertNull(AmountParser.parse("0.00", 2))
        assertNull(AmountParser.parse("-5", 0)) // ruling R8
    }

    @Test
    fun theBoundIsFifteenNinesOfMinorUnits() {
        assertEquals(999_999_999_999_999L, AmountParser.parse("999999999999999", 0))
        assertNull(AmountParser.parse("1000000000000000", 0))
        assertEquals(999_999_999_999_999L, AmountParser.parse("9999999999999.99", 2))
        assertNull(AmountParser.parse("10000000000000.00", 2))
        assertNull(AmountParser.parse("99999999999999999999999", 0)) // no overflow
    }

    @Test
    fun garbageIsNull() {
        for (input in listOf("", " ", ".", "1.2.3", "12a", "۱۲x", "--5", "+5", "1e5", "12٫5")) {
            assertNull(input, AmountParser.parse(input, 2))
        }
    }
}
