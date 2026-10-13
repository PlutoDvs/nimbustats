package com.nimbustats.app.widget

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import android.widget.ToggleButton
import com.nimbustats.app.MainActivity
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
    private var categoryId: String? = null

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
        amount.inputType = if (snapshot.currencyDecimalDigits > 0) {
            InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
        } else {
            InputType.TYPE_CLASS_NUMBER
        }
        val save = findViewById<Button>(R.id.entry_save).apply {
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

        val row = findViewById<LinearLayout>(R.id.entry_chips)
        for (chip in snapshot.chips) {
            val button = ToggleButton(this).apply {
                textOn = chip.name
                textOff = chip.name
                text = chip.name
                minHeight = dp(48)
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
            row.addView(
                button,
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                    .apply { marginEnd = dp(8) },
            )
        }

        amount.requestFocus()
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
    }

    private fun parse(text: String): Long? = AmountParser.parse(text, snapshot.currencyDecimalDigits)

    private fun save(text: String) {
        val minor = parse(text) ?: return
        WidgetBuffer.appendExpense(this, System.currentTimeMillis(), minor, categoryId)
        DrainScheduler.enqueue(this)
        // The application context: the toast outlives this dialog.
        Toast.makeText(applicationContext, snapshot.string("saved"), Toast.LENGTH_SHORT).show()
        finish()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
