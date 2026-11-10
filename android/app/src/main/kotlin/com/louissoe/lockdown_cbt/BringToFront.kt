package com.louissoe.lockdown_cbt

import android.app.ActivityManager
import android.app.PendingIntent
import android.app.ActivityOptions
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log

object BringToFront {
    private var last = 0L
    private val mainHandler = Handler(Looper.getMainLooper())

    fun run(ctx: Context) {
        val now = SystemClock.elapsedRealtime()
        if (now - last < 400) return
        last = now
        val app = ctx.applicationContext

        executeBring(app)

        // Panggil kembali setelah transisi launcher selesai (150ms & 350ms)
        mainHandler.postDelayed({ executeBring(app) }, 150)
        mainHandler.postDelayed({ executeBring(app) }, 350)
    }

    private fun executeBring(app: Context) {
        // 1. Bawa task ke depan via ActivityManager.AppTask (API 21+)
        try {
            val am = app.getSystemService(ActivityManager::class.java)
            if (am != null) {
                val tasks = am.appTasks
                if (!tasks.isNullOrEmpty()) {
                    for (task in tasks) {
                        task.moveToFront()
                    }
                }
                if (ExamSession.taskId >= 0) {
                    am.moveTaskToFront(
                        ExamSession.taskId,
                        ActivityManager.MOVE_TASK_NO_USER_ACTION
                    )
                }
            }
        } catch (e: Exception) {
            Log.w("BringToFront", "moveTaskToFront error: ${e.message}")
        }

        // 2. Bawa ke depan via Launch Intent & PendingIntent
        try {
            val launchIntent = app.packageManager.getLaunchIntentForPackage(app.packageName)?.apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            } ?: Intent(app, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            }

            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
            val pi = PendingIntent.getActivity(app, 1002, launchIntent, flags)
            try {
                if (Build.VERSION.SDK_INT >= 34) {
                    val options = ActivityOptions.makeBasic().apply {
                        setPendingIntentBackgroundActivityStartMode(
                            ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                        )
                    }
                    pi.send(options.toBundle())
                } else {
                    pi.send()
                }
            } catch (_: Exception) {
                app.startActivity(launchIntent)
            }
        } catch (e: Exception) {
            Log.w("BringToFront", "startActivity error: ${e.message}")
        }
    }
}
