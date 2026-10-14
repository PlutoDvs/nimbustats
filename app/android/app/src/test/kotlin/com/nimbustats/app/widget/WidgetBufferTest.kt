package com.nimbustats.app.widget

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WidgetBufferTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val earlier = """{"v":1,"id":"a","kind":"tracker","atUtc":1,"trackerId":"t"}"""

    /** What a power loss mid-append leaves: the start of a line and no newline. */
    private val torn = """{"v":1,"id":"b","kind":"trac"""

    private val next = """{"v":1,"id":"c","kind":"tracker","atUtc":3,"trackerId":"t"}"""

    private fun buffer(content: String? = null): File =
        File(folder.root, "widget_buffer.jsonl").apply { if (content != null) writeText(content) }

    @Test
    fun aTornTailIsClosedSoTheNextTapStartsItsOwnLine() { // D29
        val file = buffer("$earlier\n$torn")

        WidgetBuffer.appendLine(file, next)

        assertEquals("$earlier\n$torn\n$next\n", file.readText())
    }

    @Test
    fun aCleanFileGetsNoBlankLine() {
        val file = buffer("$earlier\n")

        WidgetBuffer.appendLine(file, next)

        assertEquals("$earlier\n$next\n", file.readText())
    }

    @Test
    fun aMissingFileIsCreatedHoldingTheLine() {
        val file = buffer()

        WidgetBuffer.appendLine(file, next)

        assertEquals("$next\n", file.readText())
    }
}
