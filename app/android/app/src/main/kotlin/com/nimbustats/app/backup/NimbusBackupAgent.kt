package com.nimbustats.app.backup

import android.app.backup.BackupAgentHelper
import android.app.backup.FullBackupDataOutput
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import java.io.File

/**
 * Checkpoints the WAL before Auto Backup copies the app's files (Phase 7 spec §4.2).
 *
 * In WAL mode the newest writes live in `nimbustats.sqlite-wal`. A TRUNCATE checkpoint moves
 * them into the database file and empties the WAL, so the copy holds them in one place. `super`
 * then applies the XML rules. Key/value backup is off (`fullBackupOnly`), so the helper's own
 * key/value methods never run.
 */
class NimbusBackupAgent : BackupAgentHelper() {
    override fun onFullBackup(data: FullBackupDataOutput) {
        checkpoint()
        super.onFullBackup(data)
    }

    private fun checkpoint() {
        // Flutter's getApplicationDocumentsDirectory() is this app_flutter directory.
        val file = File(getDir("flutter", Context.MODE_PRIVATE), "nimbustats.sqlite")
        if (!file.exists()) return
        try {
            // NO_LOCALIZED_COLLATORS: without it, Android adds an android_metadata table to our file.
            SQLiteDatabase.openDatabase(
                file.path,
                null,
                SQLiteDatabase.OPEN_READWRITE or
                    SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING or
                    SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            ).use { db ->
                // The pragma answers one row (busy, WAL frames, frames moved), so it is a query.
                db.rawQuery("PRAGMA wal_checkpoint(TRUNCATE)", null).use { row ->
                    if (row.moveToFirst() && row.getInt(0) != 0) {
                        Log.e(TAG, "WAL checkpoint before backup was blocked; the WAL is backed up with the file")
                    }
                }
            }
        } catch (error: Exception) {
            // The approved trade-off (spec §4.2): Android has stopped the app, so the file and its
            // WAL are a consistent pair that SQLite recovers on open. Skipping the backup would
            // trade a small risk for a certain loss.
            Log.e(TAG, "WAL checkpoint before backup failed; backing up as is", error)
        }
    }
}
