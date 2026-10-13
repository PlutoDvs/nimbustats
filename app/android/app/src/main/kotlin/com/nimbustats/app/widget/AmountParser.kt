package com.nimbustats.app.widget

/**
 * The dialog's amount as minor units for a currency with [decimalDigits] fraction digits, or null
 * (spec §7). Pure: JUnit covers it.
 *
 * It mirrors Dart's `MoneyFormatter.parse`, so the dialog accepts what the add screen accepts:
 * - Latin, Persian and Arabic-Indic digits;
 * - `,`, U+066C, a space and a no-break space are dropped;
 * - one `.`;
 * - at most [decimalDigits] fraction digits, and none for a zero-decimal currency.
 *
 * Unlike it, the dialog refuses `-` (ruling R8: it records spending) and zero (nothing to save),
 * and anything above [MAX_MINOR].
 */
object AmountParser {
    /** Fifteen nines of minor units: far above any real expense, inside a Long and a JSON number. */
    const val MAX_MINOR = 999_999_999_999_999L

    fun parse(input: String, decimalDigits: Int): Long? {
        require(decimalDigits in 0..3) { "decimalDigits $decimalDigits" }
        val text = toLatin(input).trim()
            .replace(",", "").replace("٬", "").replace(" ", "").replace(" ", "")
        if (text.isEmpty() || text.startsWith("-")) return null
        val parts = text.split('.')
        if (parts.size > 2 || parts.any { part -> part.any { it !in '0'..'9' } }) return null
        val whole = parts[0]
        val fraction = parts.getOrNull(1)
        if (whole.isEmpty() && fraction.isNullOrEmpty()) return null
        val major = whole.trimStart('0').ifEmpty { "0" }
        if (major.length > 15) return null
        val minor = when {
            fraction.isNullOrEmpty() -> 0L
            decimalDigits == 0 || fraction.length > decimalDigits -> return null
            else -> fraction.padEnd(decimalDigits, '0').toLong()
        }
        var scale = 1L
        repeat(decimalDigits) { scale *= 10 }
        val total = major.toLong() * scale + minor
        return if (total in 1..MAX_MINOR) total else null
    }

    private fun toLatin(input: String): String = buildString(input.length) {
        for (c in input) {
            append(
                when (c) {
                    in '۰'..'۹' -> '0' + (c - '۰')
                    in '٠'..'٩' -> '0' + (c - '٠')
                    else -> c
                },
            )
        }
    }
}
