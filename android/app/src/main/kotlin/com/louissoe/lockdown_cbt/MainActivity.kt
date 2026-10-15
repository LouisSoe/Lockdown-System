package com.louissoe.lockdown_cbt

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val LOCKDOWN_CHANNEL = "lockdown_channel"
    private val ANTICHEAT_CHANNEL = "anticheat_channel"
    
    private lateinit var lockdownPlugin: LockdownPlugin
    private lateinit var antiCheatPlugin: AntiCheatPlugin

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        lockdownPlugin = LockdownPlugin(this)
        antiCheatPlugin = AntiCheatPlugin(this)
        
        // Register Lockdown Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCKDOWN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableFullscreen" -> {
                        lockdownPlugin.enableFullscreen()
                        result.success(null)
                    }
                    "disableFullscreen" -> {
                        lockdownPlugin.disableFullscreen()
                        result.success(null)
                    }
                    "blockShortcuts" -> {
                        lockdownPlugin.blockShortcuts()
                        result.success(null)
                    }
                    "unblockShortcuts" -> {
                        lockdownPlugin.unblockShortcuts()
                        result.success(null)
                    }
                    "disableWindowControls" -> {
                        // Not applicable on Android
                        result.success(null)
                    }
                    "enableWindowControls" -> {
                        // Not applicable on Android
                        result.success(null)
                    }
                    "blockContextMenu" -> {
                        lockdownPlugin.blockContextMenu()
                        result.success(null)
                    }
                    "unblockContextMenu" -> {
                        lockdownPlugin.unblockContextMenu()
                        result.success(null)
                    }
                    "disableClipboard" -> {
                        lockdownPlugin.disableClipboard()
                        result.success(null)
                    }
                    "enableClipboard" -> {
                        lockdownPlugin.enableClipboard()
                        result.success(null)
                    }
                    "enableKioskMode" -> {
                        lockdownPlugin.enableKioskMode()
                        result.success(null)
                    }
                    "disableKioskMode" -> {
                        lockdownPlugin.disableKioskMode()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        
        // Register AntiCheat Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ANTICHEAT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRunningProcesses" -> {
                        val processes = antiCheatPlugin.getRunningProcesses()
                        result.success(processes)
                    }
                    "getDisplayCount" -> {
                        val count = antiCheatPlugin.getDisplayCount()
                        result.success(count)
                    }
                    "isRemoteDesktop" -> {
                        val isRemote = antiCheatPlugin.isRemoteDesktop()
                        result.success(isRemote)
                    }
                    else -> result.notImplemented()
                }
            }
    }
    
    override fun onBackPressed() {
        // Block back button during lockdown
        if (lockdownPlugin.isLocked()) {
            // Do nothing - back button is blocked
            return
        }
        super.onBackPressed()
    }
    
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && lockdownPlugin.isLocked()) {
            lockdownPlugin.hideNavigationBar()
        }
    }

    // Intercept long press untuk blokir context menu di level Activity.
    // Ini melengkapi WebView-level blocking via InAppWebViewSettings.
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (lockdownPlugin.isContextMenuBlocked() &&
            ev.action == MotionEvent.ACTION_DOWN) {
            // Tandai waktu touch down — dipakai untuk deteksi long press
            // Flutter/WebView tetap yang handle, tapi context menu
            // di level native Android sudah diblokir via openContextMenu override
        }
        return super.dispatchTouchEvent(ev)
    }

    // Blokir openContextMenu yang dipanggil oleh system saat long press terdeteksi
    override fun openContextMenu(view: View) {
        if (lockdownPlugin.isContextMenuBlocked()) {
            // Telan — tidak forward ke super, context menu tidak akan muncul
            return
        }
        super.openContextMenu(view)
    }
}
