package com.nimbustats.app.widget

import android.content.Context
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import org.json.JSONObject

data class SnapTracker(
    val id: String,
    val name: String,
    val color: Int,
    val type: String,
    val perTap: Double,
    val unit: String?,
    val todayTotal: Double,
)

data class SnapChip(val id: String, val name: String)

/** `widget_snapshot.json` as native reads it (spec 6.1). Dart writes it, and native only reads. */
class WidgetSnapshot(
    val dayKey: Int,
    val localeTag: String,
    val rtl: Boolean,
    val currencyDecimalDigits: Int,
    val currencyLabel: String,
    val trackers: List<SnapTracker>,
    val chips: List<SnapChip>,
    private val strings: Map<String, String>,
) {
    /** A label Dart sent. [parse] checked [REQUIRED_STRINGS], so these cannot miss. */
    fun string(key: String): String = strings.getValue(key)

    companion object {
        private const val VERSION = 1

        /** Every label the widget and the dialog show (spec 6.1). A snapshot lacking one does not parse. */
        val REQUIRED_STRINGS = listOf(
            "addExpense", "emptyTrackers", "entryTitle", "save", "cancel", "saved", "trackerAdd", "trackerDone",
        )

        /**
         * The current snapshot, or null. Null means either:
         * - there is none yet, which is the loading state; or
         * - it does not read, which is the error state. The cause is logged, and the next app
         *   start rewrites the snapshot (spec 6.5).
         */
        fun read(context: Context): WidgetSnapshot? {
            val json = WidgetBuffer.readSnapshot(context) ?: return null
            return try {
                parse(json)
            } catch (error: Exception) {
                Log.e(TAG, "widget snapshot unreadable; showing the loading state until the app rewrites it", error)
                null
            }
        }

        fun parse(json: String): WidgetSnapshot {
            val root = JSONObject(json)
            val version = root.getInt("v")
            require(version == VERSION) { "snapshot version $version is not $VERSION" }
            val currency = root.getJSONObject("currency")
            val digits = currency.getInt("decimalDigits")
            require(digits in 0..3) { "currency.decimalDigits $digits is not in 0..3" }
            val strings = root.getJSONObject("strings")
            val missing = REQUIRED_STRINGS.filter { strings.isNull(it) }
            require(missing.isEmpty()) { "the snapshot has no string(s) $missing" }
            val trackers = root.getJSONArray("trackers")
            val chips = root.getJSONArray("chips")
            return WidgetSnapshot(
                dayKey = root.getInt("dayKey"),
                localeTag = root.getString("localeTag"),
                rtl = root.getBoolean("rtl"),
                currencyDecimalDigits = digits,
                currencyLabel = currency.getString("label"),
                trackers = List(trackers.length()) { i ->
                    val t = trackers.getJSONObject(i)
                    SnapTracker(
                        id = t.getString("id"),
                        name = t.getString("name"),
                        color = t.getLong("color").toInt(), // ARGB stored as an unsigned 32-bit number
                        type = t.getString("type"),
                        perTap = t.getDouble("perTap"),
                        unit = if (t.isNull("unit")) null else t.getString("unit"),
                        todayTotal = t.getDouble("todayTotal"),
                    )
                },
                chips = List(chips.length()) { i ->
                    val c = chips.getJSONObject(i)
                    SnapChip(c.getString("id"), c.getString("name"))
                },
                strings = strings.keys().asSequence().associateWith { strings.getString(it) },
            )
        }
    }
}
