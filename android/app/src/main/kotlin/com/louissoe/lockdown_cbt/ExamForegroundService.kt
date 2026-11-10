package com.louissoe.lockdown_cbt

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

class ExamForegroundService : Service() {

    private val h = Handler(Looper.getMainLooper())
    private var detector: ForegroundDetector? = null
    private var tick = 0
    private var closeReported = false
    private var closedAt = 0L
    private var lastBringAt = 0L

    private val loop = object : Runnable {
        override fun run() {
            if (!ExamSession.active) { stopSelf(); return }
            try { watchdog() } catch (e: Exception) { Log.e("ExamKiosk", "watchdog", e) }
            h.postDelayed(this, 500)
        }
    }

    override fun onBind(i: Intent?): IBinder? = null

    override fun onStartCommand(i: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        EventQueue.init(applicationContext)
        detector = if (KioskStatus.hasUsageAccess(this)) ForegroundDetector(this) else null
        closeReported = false
        tick = 0
        h.removeCallbacks(loop)
        h.post(loop)
        return START_NOT_STICKY   // bila proses mati, state sesi ikut hilang; Dart memulai ulang
    }

    override fun onDestroy() {
        h.removeCallbacksAndMessages(null)
        OverlayBlocker.hide(this)
        super.onDestroy()
    }

    private fun watchdog() {
        // L4: cadangan deteksi aplikasi di depan
        detector?.poll()?.let { fg ->
            if (fg == packageName) {
                ExamSession.foreignPkg = null
            } else if (!Allowlist.isAllowed(this, fg) && !ExamSession.pinningInProgress()) {
                if (ExamSession.foreignPkg != fg)
                    EventQueue.enqueue("FOREIGN_APP", fg, dedupeMs = 1500)
                ExamSession.foreignPkg = fg
            }
        }

        if (ExamSession.active && !ExamSession.initialPinDone && KioskStatus.isPinned(this)) {
            ExamSession.initialPinDone = true
            val minGrace = ExamSession.now() + 3_000
            if (ExamSession.graceUntil < minGrace) {
                ExamSession.graceUntil = minGrace
            }
        }

        val s = KioskStatus.snapshot(this)
        val ok = s["gateOpen"] as Boolean
        val now = ExamSession.now()

        if (!ok) {
            val inGrace = ExamSession.inGrace() || ExamSession.pinningInProgress()
            if (!closeReported && !inGrace) {
                closeReported = true
                closedAt = now
                ExamSession.violations++
                if (ExamSession.hasViolationLimit) {
                    ExamSession.isLockedOut = true
                    if (ExamSession.violations > ExamSession.maxViolations) {
                        ExamSession.isBlocked = true
                    }
                }
                @Suppress("UNCHECKED_CAST")
                val missingList = s["missing"] as? List<*> ?: emptyList<Any>()
                EventQueue.enqueue("GATE_CLOSED", missingList.joinToString(","))
            }
            recover()
        } else if (closeReported) {
            closeReported = false
            EventQueue.enqueue("GATE_OPENED", "duration_ms=${now - closedAt}")
            OverlayBlocker.hide(this)
        }

        val out = s + mapOf("violations" to ExamSession.violations)
        KioskBus.emit(out)
        if (++tick % 10 == 0) EventQueue.heartbeat(out)   // 10 x 500 ms = 5 detik
    }

    // Aplikasi ujian ada di depan: cukup gerbang tertutup dan pin diminta ulang oleh MainActivity.
    // Aplikasi lain di depan: tutup dengan overlay dan tarik aplikasi ujian kembali.
    private fun recover() {
        if (ExamSession.pinningInProgress()) return
        val away = !ExamSession.hasFocus || ExamSession.foreignPkg != null
        if (!away) return
        OverlayBlocker.show(this)
        val now = ExamSession.now()
        if (now - lastBringAt >= 700) {
            lastBringAt = now
            BringToFront.run(this)
            h.postDelayed({
                if (ExamSession.active && ExamSession.lastResumeAt < now && ExamSession.foreignPkg != null)
                    EventQueue.enqueue("BRING_FRONT_FAILED", ExamSession.foreignPkg ?: "", dedupeMs = 10_000)
            }, 2000)
        }
    }

    private fun startInForeground() {
        val ch = "exam_guard"
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(
            NotificationChannel(ch, "Ujian berlangsung", NotificationManager.IMPORTANCE_LOW)
        )
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val iconRes = applicationInfo.icon.let { if (it != 0) it else android.R.drawable.ic_lock_lock }
        val n = Notification.Builder(this, ch)
            .setContentTitle("Ujian sedang berlangsung")
            .setContentText("Jangan menutup aplikasi ujian.")
            .setSmallIcon(iconRes)
            .setOngoing(true)
            .setContentIntent(pi)
            .build()
        if (Build.VERSION.SDK_INT >= 34)
            startForeground(1001, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else
            startForeground(1001, n)
    }
}
