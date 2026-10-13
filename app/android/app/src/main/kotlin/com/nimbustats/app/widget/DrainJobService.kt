package com.nimbustats.app.widget

import android.app.job.JobParameters
import android.app.job.JobService
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Drains the widget buffer after a tap (spec §2.4). The tap itself never waits for this.
 *
 * - **App engine alive:** if its Dart side has registered the drain, the job sends `drainNow`
 *   and finishes on the reply.
 * - **Otherwise:** a `notImplemented` reply, or no app engine at all, means a headless
 *   `FlutterEngine` runs `drainMain`. The engine is destroyed on `drainFinished`, or after 60 s
 *   without it.
 *
 * The job never asks to be rescheduled, so a persistent failure cannot loop. After a clean drain
 * it enqueues again only if taps arrived meanwhile (ruling R10).
 */
class DrainJobService : JobService() {
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var params: JobParameters? = null
    private val timeout = Runnable {
        Log.e(TAG, "widget drain: no result within 60 s; the buffer stays for the next app start")
        finish(ok = false)
    }

    override fun onStartJob(params: JobParameters): Boolean {
        this.params = params
        // One budget for both paths: a drainNow reply that never comes must not hold the job.
        main.postDelayed(timeout, TIMEOUT_MS)
        val app = OutsideChannelHandler.appChannel
        if (app == null) {
            runHeadless()
            return true
        }
        app.invokeMethod(
            "drainNow",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) = finish(ok = result == true)

                override fun error(code: String, message: String?, details: Any?) {
                    Log.e(TAG, "widget drain: the app engine's drain failed ($code: $message); draining headless")
                    runHeadless()
                }

                // The app engine's Dart side has not registered its drain yet.
                override fun notImplemented() = runHeadless()
            },
        )
        return true
    }

    private fun runHeadless() {
        // A late notImplemented/error reply after the job ended must not boot an engine nobody holds.
        if (params == null) return
        // The constructor initialises the FlutterLoader and registers the plugins (path_provider).
        val engine = FlutterEngine(applicationContext)
        this.engine = engine
        MethodChannel(engine.dartExecutor.binaryMessenger, OutsideChannelHandler.CHANNEL).setMethodCallHandler(
            OutsideChannelHandler(applicationContext, onDrainFinished = { ok -> main.post { finish(ok) } }),
        )
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "package:nimbustats/drain_main.dart",
                "drainMain",
            ),
        )
    }

    private fun finish(ok: Boolean) {
        main.removeCallbacks(timeout)
        engine?.destroy()
        engine = null
        val finished = params ?: return
        params = null
        jobFinished(finished, false)
        if (ok) {
            // Posted behind jobFinished's own queued message: scheduling now would stop this still-running job.
            main.post {
                try {
                    if (WidgetBuffer.lines(applicationContext).isNotEmpty()) {
                        DrainScheduler.enqueue(applicationContext, force = true)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "widget drain: the follow-up drain was not scheduled", e)
                }
            }
        }
    }

    override fun onStopJob(params: JobParameters): Boolean {
        main.removeCallbacks(timeout)
        engine?.destroy()
        engine = null
        this.params = null
        Log.e(TAG, "widget drain stopped by the system; the buffer stays for the next drain")
        return false
    }

    private companion object {
        const val TIMEOUT_MS = 60_000L
    }
}
