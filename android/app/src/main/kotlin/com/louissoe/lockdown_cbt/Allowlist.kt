package com.louissoe.lockdown_cbt

import android.content.Context
import android.view.inputmethod.InputMethodManager

object Allowlist {
    private const val SYSTEM_UI = "com.android.systemui"

    fun isSystemUi(pkg: String) = pkg == SYSTEM_UI

    fun isAllowed(ctx: Context, pkg: String): Boolean =
        pkg == ctx.packageName || pkg == SYSTEM_UI ||
            pkg in ExamSession.extraAllowed || pkg in imePackages(ctx)

    private fun imePackages(ctx: Context): Set<String> =
        ctx.getSystemService(InputMethodManager::class.java)
            ?.enabledInputMethodList?.map { it.packageName }?.toSet() ?: emptySet()
}
