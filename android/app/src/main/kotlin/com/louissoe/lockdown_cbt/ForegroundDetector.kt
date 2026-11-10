package com.louissoe.lockdown_cbt

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build

class ForegroundDetector(ctx: Context) {
    private val usm = ctx.getSystemService(UsageStatsManager::class.java)
    private var since = System.currentTimeMillis() - 3000
    private var current: String? = null

    @Suppress("DEPRECATION")
    private val resumed =
        if (Build.VERSION.SDK_INT >= 29) UsageEvents.Event.ACTIVITY_RESUMED
        else UsageEvents.Event.MOVE_TO_FOREGROUND

    fun poll(): String? {
        val usmInstance = usm ?: return null
        val now = System.currentTimeMillis()
        val events = usmInstance.queryEvents(since, now)
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType == resumed) current = e.packageName
        }
        since = now - 300   // tumpang tindih kecil agar tidak ada event terlewat
        return current
    }
}
