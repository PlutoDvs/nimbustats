package com.nimbustats.app.widget

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.text.Editable
import android.text.InputType
import android.text.TextUtils
import android.text.TextWatcher
import android.text.method.DigitsKeyListener
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.GridLayout
import android.widget.TextView
import android.widget.Toast
import android.widget.ToggleButton
import java.io.IOException
import com.nimbustats.app.MainActivity
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import com.nimbustats.app.R

/**
 * The widget's add-expense dialog (spec 7).
 *
 * It is native end to end: no Flutter engine starts, and no database opens. Save appends one
 * buffer line, enqueues the drain, shows "saved" and closes, with no spinner. Cancel, back or a
 * tap outside closes without writing.
 *
 * It has its own task affinity and is excluded from recents, so it never brings the app forward.
 * Its direction and every word come from the snapshot.
 */
class ExpenseEntryActivity : Activity() {
    private lateinit var snapshot: WidgetSnapshot
    private val chips = mutableListOf<ToggleButton>()
    private lateinit var saveButton: Button
    private var categoryId: String? = null
    private var saved = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val read = WidgetSnapshot.read(this)
        if (read == null) {
            // No snapshot: the widget is in its loading state, which opens the app instead.
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            finish()
            return
        }
        snapshot = read
        setContentView(R.layout.activity_expense_entry)
        window.decorView.layoutDirection =
            if (snapshot.rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR

        findViewById<TextView>(R.id.entry_title).text = snapshot.string("entryTitle")
        val amount = findViewById<EditText>(R.id.entry_amount)
        amount.hint = snapshot.currencyLabel
        val decimal = snapshot.currencyDecimalDigits > 0
        // A numeric inputType alone installs a 0-9 filter that drops the IME's Persian digits and
        // separators before AmountParser sees them; the raw type keeps the numeric keyboard.
        amount.keyListener = DigitsKeyListener.getInstance(AMOUNT_CHARS + if (decimal) "." else "")
        amount.setRawInputType(
            if (decimal) InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL else InputType.TYPE_CLASS_NUMBER,
        )
        val save = findViewById<Button>(R.id.entry_save).also { saveButton = it }.apply {
            text = snapshot.string("save")
            isEnabled = false
            setOnClickListener { save(amount.text.toString()) }
        }
        findViewById<Button>(R.id.entry_cancel).apply {
            text = snapshot.string("cancel")
            setOnClickListener { finish() }
        }
        amount.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) {
                save.isEnabled = parse(s?.toString().orEmpty()) != null
            }
        })
        amount.setOnEditorActionListener { _, action, _ ->
            (action == EditorInfo.IME_ACTION_DONE && save.isEnabled).also { if (it) save(amount.text.toString()) }
        }

        // Two equal columns, two rows at most (MAX_CHIPS): a long name ellipsizes in its own cell
        // instead of pushing the fourth chip past the dialog's edge (D31).
        val grid = findViewById<GridLayout>(R.id.entry_chips)
        snapshot.chips.take(MAX_CHIPS).forEachIndexed { index, chip ->
            val button = ToggleButton(this).apply {
                textOn = chip.name
                textOff = chip.name
                text = chip.name
                minHeight = dp(48)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                setBackgroundResource(R.drawable.entry_chip)
                setTextColor(getColorStateList(R.color.entry_chip_text))
                // Single-select; tapping the chosen one again leaves no chip, which is Uncategorized.
                setOnCheckedChangeListener { view, checked ->
                    if (checked) {
                        chips.filter { it !== view }.forEach { it.isChecked = false }
                        categoryId = chip.id
                    } else if (categoryId == chip.id) {
                        categoryId = null
                    }
                }
            }
            chips += button
            grid.addView(
                button,
                GridLayout.LayoutParams(
                    GridLayout.spec(GridLayout.UNDEFINED),
                    GridLayout.spec(GridLayout.UNDEFINED, 1f),
                ).apply {
                    // Width 0 and weight 1: the columns share the width equally.
                    width = 0
                    if (index % 2 == 0) marginEnd = dp(4) else marginStart = dp(4)
                    if (index >= 2) topMargin = dp(8)
                },
            )
        }

        amount.requestFocus()
    }

    private fun parse(text: String): Long? = AmountParser.parse(text, snapshot.currencyDecimalDigits)

    private fun save(text: String) {
        val minor = parse(text) ?: return
        // finish() does not stop queued clicks or the Done key, and each append has a new id.
        if (saved) return
        saved = true
        saveButton.isEnabled = false
        try {
            WidgetBuffer.appendExpense(this, System.currentTimeMillis(), minor, categoryId)
        } catch (e: IOException) {
            return keepOpen(e)
        } catch (e: RuntimeException) {
            return keepOpen(e)
        }
        try {
            DrainScheduler.enqueue(this)
        } catch (e: RuntimeException) {
            // The line is buffered; the next app start or drain picks it up.
            Log.e(TAG, "expense buffered but the drain could not be enqueued", e)
        }
        // The application context: the toast outlives this dialog.
        Toast.makeText(applicationContext, snapshot.string("saved"), Toast.LENGTH_SHORT).show()
        finish()
    }

    /** The append failed: nothing was written, so the dialog stays open with what the user typed. */
    private fun keepOpen(e: Exception) {
        Log.e(TAG, "could not buffer the expense", e)
        saved = false
        saveButton.isEnabled = true
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private companion object {
        const val MAX_CHIPS = 4

        /** What [AmountParser] reads, bar `.`: Latin, Persian, Arabic-Indic digits and the separators it drops. */
        const val AMOUNT_CHARS = "0123456789۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩,\u066C \u00A0"
    }
}
