package com.nimbustats.app.widget

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG

/**
 * Enqueues the one drain job (spec §2.4).
 *
 * There is one fixed id, and nothing is scheduled while that job is already pending or running.
 * A burst of taps is one drain, and the next tap never stops a running drain, which `schedule`
 * would do. Taps made during a run are picked up when it finishes, because [DrainJobService]
 * re-enqueues with [force].
 *
 * The job is expedited on Android 12+. Below 12, or when expedited quota is spent, it is a plain
 * job that may start at once. It has no network constraint.
 */
object DrainScheduler {
    private const val JOB_ID = 6_000

    fun enqueue(context: Context, force: Boolean = false) {
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (!force && scheduler.getPendingJob(JOB_ID) != null) return
        val component = ComponentName(context, DrainJobService::class.java)
        if (Build.VERSION.SDK_INT >= 31 &&
            scheduler.schedule(JobInfo.Builder(JOB_ID, component).setExpedited(true).build()) ==
            JobScheduler.RESULT_SUCCESS
        ) {
            return
        }
        val plain = scheduler.schedule(JobInfo.Builder(JOB_ID, component).setOverrideDeadline(0).build())
        if (plain != JobScheduler.RESULT_SUCCESS) {
            Log.e(TAG, "widget drain job was not scheduled; the next app start drains the buffer")
        }
    }
}
