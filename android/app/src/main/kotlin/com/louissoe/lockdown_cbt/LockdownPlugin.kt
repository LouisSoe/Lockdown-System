package com.louissoe.lockdown_cbt

import android.app.Activity
import android.app.ActivityManager
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager

class LockdownPlugin(private val activity: Activity) {
    private var isLocked = false
    private var contextMenuBlocked = false
    var isPinningInProgress = false

    private val mainHandler = Handler(Looper.getMainLooper())

    // Transparent Top Touch Overlay (Menelan semua gesture swipe dari atas)
    private var overlayView: View? = null
    private var windowManager: WindowManager? = null



    // Clipboard listener untuk persistent blocking
    private var clipboardManager: ClipboardManager? = null
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null
    private var clipboardBlocked = false

    // Notification blocking
    private var notificationManager: NotificationManager? = null
    private var previousInterruptionFilter: Int = NotificationManager.INTERRUPTION_FILTER_ALL

    fun enableFullscreen() {
        isLocked = true
        activity.runOnUiThread {
            activity.window.apply {
                addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                addFlags(WindowManager.LayoutParams.FLAG_SECURE)  // Prevent screenshots
                setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    attributes.layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }

                val hideBars = {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
                        setDecorFitsSystemWindows(false)
                        insetsController?.let { controller ->
                            controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                            controller.systemBarsBehavior =
                                WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                        }
                    } else {
                        addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
                    }
                    @Suppress("DEPRECATION")
                    decorView.systemUiVisibility = (
                        View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        or View.SYSTEM_UI_FLAG_FULLSCREEN
                        or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    )
                }

                hideBars()
                decorView.post { hideBars() }
            }
        }
        println("✓ Fullscreen enabled")
    }

    fun disableFullscreen() {
        isLocked = false
        activity.runOnUiThread {
            activity.window.apply {
                clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
                clearFlags(WindowManager.LayoutParams.FLAG_SECURE)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setDecorFitsSystemWindows(true)
                    insetsController?.show(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                }
                @Suppress("DEPRECATION")
                decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
            }
        }
        println("✓ Fullscreen disabled")
    }

    fun blockShortcuts() {
        hideNavigationBar()
        println("✓ Shortcuts blocked")
    }

    fun unblockShortcuts() {
        println("✓ Shortcuts unblocked")
    }

    fun hideNavigationBar() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            activity.window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            )
        }
    }

    // ---------------------------------------------------------------
    // Blokir Notifikasi: Set DND (Do Not Disturb) ke INTERRUPTION_FILTER_NONE
    // ---------------------------------------------------------------
    fun blockNotifications() {
        try {
            notificationManager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (notificationManager!!.isNotificationPolicyAccessGranted) {
                    previousInterruptionFilter = notificationManager!!.currentInterruptionFilter
                    notificationManager!!.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
                    println("✓ Notifications blocked (DND: INTERRUPTION_FILTER_NONE)")
                } else {
                    println("⚠ Notification policy access not granted")
                }
            } else {
                println("⚠ Android < 6.0: DND policy tidak tersedia")
            }
        } catch (e: Exception) {
            println("✗ Block notifications error: ${e.message}")
        }
    }

    fun unblockNotifications() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (notificationManager?.isNotificationPolicyAccessGranted == true) {
                    notificationManager?.setInterruptionFilter(previousInterruptionFilter)
                    println("✓ Notifications restored (filter: $previousInterruptionFilter)")
                }
            }
            notificationManager = null
        } catch (e: Exception) {
            println("✗ Unblock notifications error: ${e.message}")
        }
    }

    fun isNotificationPolicyGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val nm = activity.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        return nm?.isNotificationPolicyAccessGranted == true
    }

    fun openNotificationPolicySettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                activity.startActivity(intent)
                println("✓ Opened Notification Policy Settings")
            } catch (e: Exception) {
                println("✗ Cannot open notification policy settings: ${e.message}")
            }
        }
    }

    // ---------------------------------------------------------------
    // Cek apakah izin "Tampilkan di atas aplikasi lain" aktif
    // ---------------------------------------------------------------
    fun isOverlayPermissionGranted(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ sudah menggunakan native LockTask mode, overlay tidak diperlukan
            return true
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(activity)
        } else {
            true
        }
    }

    fun openOverlaySettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + activity.packageName)
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                activity.startActivity(intent)
                println("✓ Opened Overlay Settings")
            } catch (e: Exception) {
                println("✗ Cannot open overlay settings: ${e.message}")
            }
        }
    }

    // ---------------------------------------------------------------
    // Pasang Lapisan Transparan di Ujung Atas Layar (Transparent Touch Overlay)
    // ---------------------------------------------------------------
    // Pasang Lapisan Transparan di Ujung Atas Layar (Transparent Touch Overlay)
    // Dinonaktifkan karena gesture status bar sudah ditangani secara instan via onWindowFocusChanged
    // dan overlay tambahan berisiko memblokir sentuhan header WebView / memicu tapjacking filter.
    // ---------------------------------------------------------------
    fun addTopOverlay() {
        println("ℹ addTopOverlay: Proteksi status bar ditangani secara murni via event onWindowFocusChanged")
    }

    fun removeTopOverlay() {
        // No-op
    }

    // ---------------------------------------------------------------
    // Tutup panel notifikasi / status bar (Trigger-based)
    // Menggunakan Broadcast ACTION_CLOSE_SYSTEM_DIALOGS (resmi & sangat efektif di Android 8)
    // dan Fallback Reflection StatusBarManager tanpa polling/looping.
    // ---------------------------------------------------------------
    fun collapseStatusBar() {
        collapseInternal()
        // Panggil ulang 100ms kemudian agar tarikan swipe status bar yang sedang bergerak langsung terinterupsi
        mainHandler.postDelayed({
            collapseInternal()
        }, 100)
    }

    private fun collapseInternal() {
        try {
            @Suppress("WrongConstant")
            val statusBarService = activity.getSystemService("statusbar")
            val statusBarManager = Class.forName("android.app.StatusBarManager")
            val collapseMethod = try {
                statusBarManager.getMethod("collapsePanels")
            } catch (e1: Exception) {
                statusBarManager.getMethod("collapse")
            }
            collapseMethod.invoke(statusBarService)
        } catch (_: Exception) {}

        // ACTION_CLOSE_SYSTEM_DIALOGS sangat ampuh di Android 8-10,
        // hanya kirim jika TIDAK sedang menunggu persetujuan dialog pin sistem di Android 10+
        if (!isPinningInProgress) {
            try {
                @Suppress("DEPRECATION")
                activity.sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))
            } catch (_: Exception) {}
        }
    }

    // ---------------------------------------------------------------
    // Trigger pemindahan aplikasi kembali ke paling depan seketika (Anti-Exit)
    // Menggunakan izin REORDER_TASKS dan MOVE_TASK_NO_USER_ACTION secara langsung
    // TANPA memanggil startActivity (sehingga bebas dari penundaan 10 detik stopAppSwitches dan bebas freeze)
    // ---------------------------------------------------------------
    fun bringAppToFront() {
        if (!isLocked) return

        if (!isPinningInProgress) {
            try {
                @Suppress("DEPRECATION")
                activity.sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))
            } catch (_: Exception) {}
        }

        // Panggil langsung seketika
        try {
            val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            am?.moveTaskToFront(activity.taskId, ActivityManager.MOVE_TASK_NO_USER_ACTION)
        } catch (_: Exception) {}

        // Panggil kembali 150ms dan 300ms kemudian untuk menangkap task setelah transisi launcher selesai
        mainHandler.postDelayed({
            try {
                val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                am?.moveTaskToFront(activity.taskId, ActivityManager.MOVE_TASK_NO_USER_ACTION)
            } catch (_: Exception) {}
        }, 150)

        mainHandler.postDelayed({
            try {
                val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                am?.moveTaskToFront(activity.taskId, ActivityManager.MOVE_TASK_NO_USER_ACTION)
            } catch (_: Exception) {}
        }, 300)
    }

    fun setLocked(locked: Boolean) {
        isLocked = locked
        println("✓ Lockdown active state set to: $locked")
    }

    // ---------------------------------------------------------------
    // Kiosk Mode (Screen Pinning / Lock Task)
    // ---------------------------------------------------------------
    fun enableKioskMode() {
        isLocked = true

        activity.runOnUiThread {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try {
                    val activityManager = activity.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                    if (activityManager?.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_NONE) {
                        // Lindungi dialog konfirmasi pin layar sistem di semua versi Android (termasuk Android 8)
                        isPinningInProgress = true
                        mainHandler.postDelayed({
                            if (isPinningInProgress) {
                                isPinningInProgress = false
                                println("ℹ isPinningInProgress timeout expired")
                            }
                        }, 2500)

                        activity.startLockTask()
                        println("✓ App pinned (Lock Task Mode requested)")
                    }
                } catch (e: Exception) {
                    isPinningInProgress = false
                    println("✗ Kiosk mode error: ${e.message}")
                }
            }
        }
    }

    fun disableKioskMode() {
        isLocked = false
        isPinningInProgress = false

        activity.runOnUiThread {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try {
                    val activityManager = activity.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                    if (activityManager?.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE) {
                        activity.stopLockTask()
                        println("✓ Kiosk mode disabled")
                    }
                } catch (e: Exception) {
                    println("✗ Disable kiosk error: ${e.message}")
                }
            }
        }
    }

    // Disable clipboard secara persistent via OnPrimaryClipChangedListener.
    fun disableClipboard() {
        clipboardBlocked = true
        clipboardManager = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

        try {
            val emptyClip = ClipData.newPlainText("", "")
            clipboardManager?.setPrimaryClip(emptyClip)
        } catch (e: Exception) {
            println("✗ Clear clipboard error: ${e.message}")
        }

        if (clipboardListener == null) {
            clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
                if (clipboardBlocked) {
                    try {
                        val emptyClip = ClipData.newPlainText("", "")
                        clipboardManager?.setPrimaryClip(emptyClip)
                    } catch (e: Exception) {
                        println("✗ Clipboard clear listener error: ${e.message}")
                    }
                }
            }
            clipboardManager?.addPrimaryClipChangedListener(clipboardListener!!)
        }
        println("✓ Clipboard disabled (persistent)")
    }

    fun enableClipboard() {
        clipboardBlocked = false
        clipboardListener?.let {
            clipboardManager?.removePrimaryClipChangedListener(it)
            clipboardListener = null
        }
        clipboardManager = null
        println("✓ Clipboard enabled")
    }

    fun blockContextMenu() {
        contextMenuBlocked = true
        println("✓ Context menu blocked")
    }

    fun unblockContextMenu() {
        contextMenuBlocked = false
        println("✓ Context menu unblocked")
    }

    fun isLocked(): Boolean = isLocked

    fun isContextMenuBlocked(): Boolean = contextMenuBlocked

    fun destroy() {
        removeTopOverlay()
    }
}
