package com.louissoe.lockdown_cbt

import android.Manifest
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val LOCKDOWN_CHANNEL = "lockdown_channel"
    private val ANTICHEAT_CHANNEL = "anticheat_channel"
    private var lockdownPlugin: LockdownPlugin? = null
    private var antiCheatPlugin: AntiCheatPlugin? = null

    private var autoPinAt = 0L
    private var autoPinCount = 0
    private var notifAsked = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        ExamSession.taskId = taskId
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        EventQueue.init(applicationContext)
        val messenger = engine.dartExecutor.binaryMessenger

        // L1..L7 Exam Kiosk channels
        EventChannel(messenger, "exam_kiosk/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    KioskBus.reset()
                    KioskBus.sink = sink
                    KioskBus.emit(currentStatus())
                }
                override fun onCancel(args: Any?) { KioskBus.sink = null }
            }
        )

        MethodChannel(messenger, "exam_kiosk/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(currentStatus())
                "startExam" -> { startExam(call); result.success(null) }
                "stopExam" -> { stopExam(); result.success(null) }
                "requestPin" -> { autoPinCount = 0; requestPin(force = true); result.success(null) }
                "unlockExam" -> {
                    val code = call.argument<String>("code") ?: ""
                    val success = ExamSession.unlock(code)
                    if (success) {
                        autoPinCount = 0
                        requestPin(force = true)
                        KioskBus.emit(currentStatus())
                    }
                    result.success(success)
                }
                "resetViolations" -> {
                    ExamSession.resetViolations()
                    autoPinCount = 0
                    requestPin(force = true)
                    KioskBus.emit(currentStatus())
                    result.success(null)
                }
                "openSetting" -> { openSetting(call.argument<String>("name") ?: ""); result.success(null) }
                else -> result.notImplemented()
            }
        }

        // Backward compatibility for existing lockdown_channel & anticheat_channel
        lockdownPlugin = LockdownPlugin(this)
        antiCheatPlugin = AntiCheatPlugin(this)

        MethodChannel(messenger, LOCKDOWN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableFullscreen" -> {
                    window.addFlags(
                        WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    )
                    lockdownPlugin?.enableFullscreen()
                    result.success(null)
                }
                "disableFullscreen" -> {
                    if (!ExamSession.active) {
                        window.clearFlags(
                            WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                        )
                        lockdownPlugin?.disableFullscreen()
                    }
                    result.success(null)
                }
                "blockShortcuts", "unblockShortcuts",
                "disableWindowControls", "enableWindowControls",
                "blockContextMenu", "unblockContextMenu" -> result.success(null)
                "disableClipboard" -> {
                    lockdownPlugin?.disableClipboard()
                    result.success(null)
                }
                "enableClipboard" -> {
                    lockdownPlugin?.enableClipboard()
                    result.success(null)
                }
                "enableKioskMode" -> {
                    requestPin()
                    result.success(null)
                }
                "disableKioskMode" -> {
                    try { stopLockTask() } catch (_: Exception) {}
                    result.success(null)
                }
                "blockNotifications", "unblockNotifications" -> result.success(null)
                "isNotificationPolicyGranted" -> {
                    val nm = getSystemService(android.app.NotificationManager::class.java)
                    result.success(nm?.isNotificationPolicyAccessGranted ?: true)
                }
                "openNotificationPolicySettings" -> {
                    openSetting("notif")
                    result.success(null)
                }
                "isOverlayPermissionGranted" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "openOverlaySettings" -> {
                    openSetting("overlay")
                    result.success(null)
                }
                "addTopOverlay", "removeTopOverlay" -> result.success(null)
                "setLockState" -> result.success(null)
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, ANTICHEAT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRunningProcesses" -> result.success(antiCheatPlugin?.getRunningProcesses() ?: emptyList<String>())
                "getDisplayCount" -> result.success(antiCheatPlugin?.getDisplayCount() ?: 1)
                "isRemoteDesktop" -> result.success(antiCheatPlugin?.isRemoteDesktop() ?: false)
                else -> result.notImplemented()
            }
        }
    }

    private fun currentStatus(): Map<String, Any?> =
        KioskStatus.snapshot(this) + mapOf("violations" to ExamSession.violations)

    // ---- siklus ujian ----

    private fun startExam(call: MethodCall) {
        ExamSession.apply {
            apiBase = call.argument<String>("apiBase") ?: ""
            token = call.argument<String>("token") ?: ""
            examId = call.argument<String>("examId") ?: ""
            studentId = call.argument<String>("studentId") ?: ""
            maxViolations = call.argument<Int>("maxViolations") ?: 2
            hasViolationLimit = call.argument<Boolean>("hasViolationLimit") ?: true
            violations = 0
            isLockedOut = false
            isBlocked = false
            initialPinDone = false
            foreignPkg = null
            graceUntil = now() + 10_000
            taskId = this@MainActivity.taskId
            active = true
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )
        lockdownPlugin?.enableFullscreen()
        setHomeAlias(true)
        startForegroundService(Intent(this, ExamForegroundService::class.java))
        EventQueue.enqueue("EXAM_STARTED")
        applyDeviceOwnerPolicy()
        autoPinCount = 0
        requestPin(force = true)
    }

    private fun stopExam() {
        EventQueue.enqueue("EXAM_ENDED")
        ExamSession.active = false
        try { stopLockTask() } catch (_: Exception) {}
        releaseDeviceOwnerPolicy()
        window.clearFlags(
            WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )
        setHomeAlias(false)
        OverlayBlocker.hide(this)
        stopService(Intent(this, ExamForegroundService::class.java))
        KioskBus.emit(currentStatus())
    }

    private fun applyDeviceOwnerPolicy() {
        val dpm = getSystemService(DevicePolicyManager::class.java) ?: return
        if (!dpm.isDeviceOwnerApp(packageName)) return
        val admin = ComponentName(this, LockdownAdminReceiver::class.java)
        try {
            dpm.setLockTaskPackages(admin, arrayOf(packageName))
            if (Build.VERSION.SDK_INT >= 28) dpm.setLockTaskFeatures(admin, 0)
            dpm.setStatusBarDisabled(admin, true)
            dpm.setKeyguardDisabled(admin, true)
            dpm.setScreenCaptureDisabled(admin, true)
            EventQueue.enqueue("DEVICE_OWNER_ACTIVE")
        } catch (e: Exception) {
            EventQueue.enqueue("DEVICE_OWNER_FAILED", e.message ?: "")
        }
    }

    private fun releaseDeviceOwnerPolicy() {
        val dpm = getSystemService(DevicePolicyManager::class.java) ?: return
        if (!dpm.isDeviceOwnerApp(packageName)) return
        val admin = ComponentName(this, LockdownAdminReceiver::class.java)
        try {
            dpm.setStatusBarDisabled(admin, false)
            dpm.setKeyguardDisabled(admin, false)
            dpm.setScreenCaptureDisabled(admin, false)
        } catch (_: Exception) {}
    }

    // ---- pin (L1) ----

    private var lastPinRequestAt = 0L

    private fun requestPin(force: Boolean = false) {
        val now = ExamSession.now()
        if (!ExamSession.active) return
        if (KioskStatus.isPinned(this)) {
            autoPinCount = 0
            return
        }
        // Debounce: cegah spam pemanggilan startLockTask berulang yang menyebabkan notifikasi/toast beruntun
        if (!force && (now - lastPinRequestAt < 3500L || ExamSession.pinningInProgress())) {
            return
        }
        lastPinRequestAt = now
        ExamSession.markPinning(4000L)
        try {
            startLockTask()
        } catch (e: Exception) {
            EventQueue.enqueue("PIN_FAILED", e.message ?: "", dedupeMs = 5000)
        }
    }

    // Maksimal 3 percobaan otomatis, jarak minimal 5 detik. HANYA saat start pertama kali sebelum initialPinDone.
    private fun autoPin() {
        if (KioskStatus.isPinned(this)) { autoPinCount = 0; return }
        if (!ExamSession.initialPinDone) {
            val now = ExamSession.now()
            if (autoPinCount < 3 && now - autoPinAt > 5000 && !ExamSession.pinningInProgress()) {
                autoPinAt = now
                autoPinCount++
                requestPin(force = false)
            }
        }
    }

    // ---- siklus activity ----

    override fun onResume() {
        super.onResume()
        ExamSession.taskId = taskId
        ExamSession.lastResumeAt = ExamSession.now()
        if (!ExamSession.isLockedOut && !ExamSession.isBlocked) {
            ExamSession.foreignPkg = null
        }
        OverlayBlocker.hide(this)
        updateWindowMode()
        if (ExamSession.active) {
            if (KioskStatus.isPinned(this)) {
                ExamSession.initialPinDone = true
                // Pertahankan buffer grace period minimal 3 detik agar transisi UI & window focus selesai
                val minGrace = ExamSession.now() + 3_000
                if (ExamSession.graceUntil < minGrace) {
                    ExamSession.graceUntil = minGrace
                }
            } else {
                autoPin()
            }
        }
        KioskBus.emit(currentStatus())
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        ExamSession.hasFocus = hasFocus
        updateWindowMode()
        if (hasFocus) {
            if (!ExamSession.isLockedOut && !ExamSession.isBlocked) {
                ExamSession.foreignPkg = null
            }
            OverlayBlocker.hide(this)
            // HANYA auto-pin jika pin pertama belum pernah selesai (saat start awal).
            // Jika terjadi pelanggaran keluar dari pin, siswa HARUS membaca peringatan dan klik tombol sendiri.
            if (ExamSession.active && !ExamSession.initialPinDone && !KioskStatus.isPinned(this) && !ExamSession.isLockedOut && !ExamSession.isBlocked) {
                requestPin(force = false)
            }
            KioskBus.emit(currentStatus())
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        updateWindowMode()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (ExamSession.active) EventQueue.enqueue("USER_LEAVE_HINT", dedupeMs = 1500)
    }

    override fun onDestroy() {
        if (ExamSession.active)
            EventQueue.enqueue("ACTIVITY_DESTROYED", "finishing=$isFinishing")
        super.onDestroy()
    }

    private fun updateWindowMode() {
        ExamSession.multiWindow = isInMultiWindowMode || isInPictureInPictureMode
    }

    // ---- pengaturan sistem untuk wizard ----

    private fun setHomeAlias(enabled: Boolean) {
        val cn = ComponentName(
            packageName,
            MainActivity::class.java.name.substringBeforeLast('.') + ".ExamHomeAlias"
        )
        try {
            packageManager.setComponentEnabledSetting(
                cn,
                if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
        } catch (_: Exception) {}
    }

    private fun openSetting(name: String) {
        val pkgUri = Uri.parse("package:$packageName")
        val intent = when (name) {
            "guard" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "overlay" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, pkgUri)
            "battery" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pkgUri)
            "usage" -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            "home" -> { setHomeAlias(true); Intent(Settings.ACTION_HOME_SETTINGS) }
            "notif" -> {
                val needAsk = Build.VERSION.SDK_INT >= 33 && !notifAsked &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                if (needAsk) {
                    notifAsked = true
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                    return
                }
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
            else -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkgUri)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkgUri))
        }
    }
}
