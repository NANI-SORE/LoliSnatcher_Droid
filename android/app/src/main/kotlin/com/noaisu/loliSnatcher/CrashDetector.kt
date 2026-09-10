package com.noaisu.loliSnatcher

import android.app.ActivityManager
import android.content.Context
import android.os.Build

/**
 * Persists fatal Java/Kotlin crashes and, on Android 11+, also checks Android's
 * process-exit history so native crashes are not missed.
 */
object CrashDetector {
    private const val PREFS_NAME = "crash_detector"
    private const val CRASH_PENDING = "crash_pending"
    private const val LAST_CHECKED_EXIT = "last_checked_exit"

    @Volatile
    private var initialized = false

    fun initialize(context: Context) {
        if (initialized) return
        synchronized(this) {
            if (initialized) return

            val appContext = context.applicationContext
            val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                // commit() is intentional: the process is about to terminate.
                appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(CRASH_PENDING, true)
                    .commit()
                previousHandler?.uncaughtException(thread, throwable)
            }
            initialized = true
        }
    }

    fun consumePreviousCrash(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        var crashed = prefs.getBoolean(CRASH_PENDING, false)
        var newestExitTimestamp = prefs.getLong(LAST_CHECKED_EXIT, 0L)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            for (exit in activityManager.getHistoricalProcessExitReasons(context.packageName, 0, 8)) {
                if (exit.timestamp <= newestExitTimestamp) continue
                newestExitTimestamp = maxOf(newestExitTimestamp, exit.timestamp)
                if (
                    exit.reason == android.app.ApplicationExitInfo.REASON_CRASH ||
                    exit.reason == android.app.ApplicationExitInfo.REASON_CRASH_NATIVE
                ) {
                    crashed = true
                }
            }
        }

        prefs.edit()
            .putBoolean(CRASH_PENDING, false)
            .putLong(LAST_CHECKED_EXIT, newestExitTimestamp)
            .apply()
        return crashed
    }
}
