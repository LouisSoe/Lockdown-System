package com.louissoe.lockdown_cbt

import android.Manifest
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.ActivityManager
import android.app.AppOpsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.text.TextUtils
import android.view.accessibility.AccessibilityManager

object KioskStatus {

    fun isPinned(ctx: Context): Boolean =
        ctx.getSystemService(ActivityManager::class.java).lockTaskModeState !=
            ActivityManager.LOCK_TASK_MODE_NONE

    @Suppress("DEPRECATION")
    fun hasUsageAccess(ctx: Context): Boolean {
        val ops = ctx.getSystemService(AppOpsManager::class.java)
        val mode = if (Build.VERSION.SDK_INT >= 29)
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        else
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun isDefaultHome(ctx: Context): Boolean {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val ri = ctx.packageManager.resolveActivity(i, PackageManager.MATCH_DEFAULT_ONLY)
        return ri?.activityInfo?.packageName == ctx.packageName
    }

    fun isGuardEnabled(ctx: Context): Boolean {
        // 1. Jika instance service sudah terkoneksi aktif di memory
        if (ExamGuardService.connected) return true

        // 2. Cek apakah aktif di AccessibilityManager sistem Android
        try {
            val am = ctx.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
            if (am != null) {
                val enabledServices = am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                for (service in enabledServices) {
                    val id = service.id ?: ""
                    val serviceInfo = service.resolveInfo?.serviceInfo
                    val sName = serviceInfo?.name ?: ""
                    val sPkg = serviceInfo?.packageName ?: ""
                    if (id.contains(ctx.packageName, ignoreCase = true) || sPkg.equals(ctx.packageName, ignoreCase = true)) {
                        if (id.contains("ExamGuardService", ignoreCase = true) || sName.contains("ExamGuardService", ignoreCase = true)) {
                            return true
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        // 3. Cek langsung dari Settings.Secure Android (tetap true meski app baru restart)
        try {
            val settingValue = Settings.Secure.getString(
                ctx.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
            if (!settingValue.isNullOrEmpty()) {
                if (settingValue.contains("ExamGuardService", ignoreCase = true)) {
                    return true
                }
                val splitter = TextUtils.SimpleStringSplitter(':')
                splitter.setString(settingValue)
                val target1 = ComponentName(ctx, ExamGuardService::class.java).flattenToString()
                val target2 = "${ctx.packageName}/.${ExamGuardService::class.java.simpleName}"
                val target3 = "${ctx.packageName}/${ExamGuardService::class.java.name}"
                while (splitter.hasNext()) {
                    val comp = splitter.next()
                    if (comp.equals(target1, ignoreCase = true) ||
                        comp.equals(target2, ignoreCase = true) ||
                        comp.equals(target3, ignoreCase = true) ||
                        comp.contains("ExamGuardService", ignoreCase = true)) {
                        return true
                    }
                }
            }
        } catch (_: Exception) {}

        return false
    }

    fun snapshot(ctx: Context): Map<String, Any?> {
        val guard = isGuardEnabled(ctx)
        val overlay = Settings.canDrawOverlays(ctx)
        val battery = ctx.getSystemService(PowerManager::class.java)
            .isIgnoringBatteryOptimizations(ctx.packageName)
        val notif = Build.VERSION.SDK_INT < 33 ||
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val pinned = isPinned(ctx)
        val inGrace = ExamSession.inGrace() || ExamSession.pinningInProgress()
        val focus = ExamSession.hasFocus || inGrace
        val single = !ExamSession.multiWindow
        val clear = ExamSession.foreignPkg == null

        val missing = buildList {
            if (!guard) add("guard")
            if (!overlay) add("overlay")
            if (!battery) add("battery")
            if (!notif) add("notif")
            if (ExamSession.active) {
                if (!pinned && !inGrace) add("pinned")
                if (!focus && !inGrace) add("focus")
                if (!single) add("singleWindow")
                if (!clear && !inGrace) add("foreignApp")
            }
        }
        val gateOpen = ExamSession.active && missing.isEmpty() && !ExamSession.isLockedOut && !ExamSession.isBlocked
        val state = when {
            !ExamSession.active -> "PREFLIGHT"
            ExamSession.isBlocked -> "BLOCKED"
            ExamSession.isLockedOut -> "LOCKED_OUT"
            gateOpen -> "AMAN"
            else -> "PELANGGARAN"
        }
        return mapOf(
            "state" to state,
            "active" to ExamSession.active,
            "gateOpen" to gateOpen,
            "isLockedOut" to ExamSession.isLockedOut,
            "isBlocked" to ExamSession.isBlocked,
            "violations" to ExamSession.violations,
            "maxViolations" to ExamSession.maxViolations,
            "hasViolationLimit" to ExamSession.hasViolationLimit,
            "prereqOk" to (guard && overlay && battery && notif),
            "guard" to guard,
            "overlay" to overlay,
            "battery" to battery,
            "notif" to notif,
            "usage" to hasUsageAccess(ctx),
            "home" to isDefaultHome(ctx),
            "pinned" to pinned,
            "focus" to focus,
            "singleWindow" to single,
            "foreignPkg" to ExamSession.foreignPkg,
            "missing" to missing,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }
}
