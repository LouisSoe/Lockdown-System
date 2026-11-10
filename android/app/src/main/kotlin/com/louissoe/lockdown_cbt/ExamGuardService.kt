package com.louissoe.lockdown_cbt

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent

class ExamGuardService : AccessibilityService() {

    companion object {
        @Volatile var connected = false
    }

    private var lastShadeAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        connected = true
        EventQueue.init(applicationContext)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        connected = false
        if (ExamSession.active) EventQueue.enqueue("GUARD_DISABLED")
        return super.onUnbind(intent)
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(e: AccessibilityEvent) {
        if (!ExamSession.active || e.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = e.packageName?.toString() ?: return

        if (pkg == packageName) {
            ExamSession.foreignPkg = null
            OverlayBlocker.hide(this)
            return
        }
        val inGrace = ExamSession.inGrace() || ExamSession.pinningInProgress()
        if (Allowlist.isSystemUi(pkg)) {
            if (!inGrace) closeShade()
            return
        }
        if (Allowlist.isAllowed(this, pkg) || inGrace) return

        ExamSession.foreignPkg = pkg
        ExamSession.violations++
        if (ExamSession.hasViolationLimit && ExamSession.violations > ExamSession.maxViolations) {
            ExamSession.isBlocked = true
        } else {
            ExamSession.isLockedOut = true
        }
        KioskBus.emit(KioskStatus.snapshot(this))
        EventQueue.enqueue("FOREIGN_APP", pkg, dedupeMs = 1500)
        OverlayBlocker.show(this)
        closeShade()
        BringToFront.run(this)
    }

    @Suppress("DEPRECATION")
    private fun closeShade() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastShadeAt < 300) return
        lastShadeAt = now
        try {
            if (Build.VERSION.SDK_INT >= 31)
                performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
            else
                sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))
        } catch (_: Exception) {}
    }
}
