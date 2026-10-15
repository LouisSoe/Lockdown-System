package com.louissoe.lockdown_cbt

import android.app.Activity
import android.app.ActivityManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.view.View
import android.view.WindowManager

class LockdownPlugin(private val activity: Activity) {
    private var isLocked = false
    private var contextMenuBlocked = false

    // Clipboard listener untuk persistent blocking
    private var clipboardManager: ClipboardManager? = null
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null
    private var clipboardBlocked = false

    fun enableFullscreen() {
        activity.window.apply {
            addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            addFlags(WindowManager.LayoutParams.FLAG_SECURE)  // Prevent screenshots

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                attributes.layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }

            decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
        }
        println("✓ Fullscreen enabled")
    }

    fun disableFullscreen() {
        activity.window.apply {
            clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            clearFlags(WindowManager.LayoutParams.FLAG_SECURE)

            decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
        }
        println("✓ Fullscreen disabled")
    }

    fun blockShortcuts() {
        // Android doesn't have traditional shortcuts like Windows
        // But we can ensure navigation bar stays hidden
        hideNavigationBar()
        println("✓ Shortcuts blocked")
    }

    fun unblockShortcuts() {
        println("✓ Shortcuts unblocked")
    }

    fun hideNavigationBar() {
        activity.window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            or View.SYSTEM_UI_FLAG_FULLSCREEN
            or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        )
    }

    fun enableKioskMode() {
        isLocked = true

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                activity.startLockTask()
                println("✓ Kiosk mode enabled (Lock Task)")
            } catch (e: Exception) {
                println("✗ Kiosk mode error: ${e.message}")
                println("⚠ Device admin permission may be required")
                // Fallback: just set the flag
                pinApp()
            }
        } else {
            pinApp()
        }
    }

    fun disableKioskMode() {
        isLocked = false

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

    private fun pinApp() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val activityManager = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            if (activityManager.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_NONE) {
                try {
                    activity.startLockTask()
                    println("✓ App pinned")
                } catch (e: Exception) {
                    println("✗ Pin app error: ${e.message}")
                }
            }
        }
    }

    // Disable clipboard secara persistent via OnPrimaryClipChangedListener.
    // Setiap kali user Ctrl+C / long-press copy, listener langsung mengosongkan clipboard.
    fun disableClipboard() {
        clipboardBlocked = true
        clipboardManager = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

        // Kosongkan clipboard saat ini
        try {
            val emptyClip = ClipData.newPlainText("", "")
            clipboardManager?.setPrimaryClip(emptyClip)
        } catch (e: Exception) {
            println("✗ Clear clipboard error: ${e.message}")
        }

        // Pasang listener persistent
        if (clipboardListener == null) {
            clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
                if (clipboardBlocked) {
                    try {
                        // Timpa konten clipboard dengan string kosong setiap kali berubah
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

    // Re-enable clipboard dan lepas listener
    fun enableClipboard() {
        clipboardBlocked = false
        clipboardListener?.let {
            clipboardManager?.removePrimaryClipChangedListener(it)
            clipboardListener = null
        }
        clipboardManager = null
        println("✓ Clipboard enabled")
    }

    // blockContextMenu di Android dihandle di dua tempat:
    // 1. Flag ini dibaca oleh MainActivity.dispatchTouchEvent untuk intercept long press
    // 2. WebView context menu diblokir via InAppWebViewSettings (disableContextMenu)
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
}
