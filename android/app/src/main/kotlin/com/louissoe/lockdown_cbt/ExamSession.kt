package com.louissoe.lockdown_cbt

import android.os.SystemClock

object ExamSession {
    @Volatile var active = false
    @Volatile var apiBase = ""
    @Volatile var token = ""
    @Volatile var examId = ""
    @Volatile var studentId = ""
    @Volatile var extraAllowed: Set<String> = emptySet()

    @Volatile var hasFocus = true
    @Volatile var multiWindow = false
    @Volatile var foreignPkg: String? = null
    @Volatile var taskId = -1
    @Volatile var lastResumeAt = 0L

    @Volatile var maxViolations = 2
    @Volatile var hasViolationLimit = true
    @Volatile var violations = 0
    @Volatile var isLockedOut = false
    @Volatile var isBlocked = false
    @Volatile var initialPinDone = false
    @Volatile var graceUntil = 0L
    @Volatile var pinningUntil = 0L

    fun now(): Long = SystemClock.elapsedRealtime()
    fun inGrace() = now() < graceUntil
    fun pinningInProgress() = now() < pinningUntil
    fun markPinning(ms: Long = 4_000) { pinningUntil = now() + ms }

    fun resetViolations() {
        violations = 0
        isLockedOut = false
        isBlocked = false
        initialPinDone = true
        graceUntil = 0L
        pinningUntil = 0L
    }

    fun unlock(code: String): Boolean {
        // Jika sudah diblokir permanen (pelanggaran > maxViolations), token tidak bisa membuka
        if (isBlocked) {
            return false
        }

        // Buka kunci pelanggaran toleransi (violations <= maxViolations)
        return if (code.isNotBlank()) {
            isLockedOut = false
            foreignPkg = null
            initialPinDone = true
            graceUntil = now() + 8_000
            pinningUntil = now() + 5_000
            true
        } else {
            false
        }
    }
}
