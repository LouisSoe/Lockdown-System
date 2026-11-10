package com.louissoe.lockdown_cbt

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

object OverlayBlocker {
    private var view: View? = null
    private val main = Handler(Looper.getMainLooper())

    fun show(ctx: Context) {
        if (view != null || !Settings.canDrawOverlays(ctx)) return
        val app = ctx.applicationContext
        val wm = app.getSystemService(WindowManager::class.java) ?: return

        val container = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.BLACK)
            isClickable = true
            isFocusable = true
            setOnClickListener {
                BringToFront.run(app)
            }

            val tvTitle = TextView(app).apply {
                text = "Kembali ke aplikasi ujian..."
                setTextColor(Color.WHITE)
                textSize = 18f
                gravity = Gravity.CENTER
            }
            val tvSub = TextView(app).apply {
                text = "Menarik kembali ke lembar ujian (ketuk jika tidak terbuka otomatis)"
                setTextColor(Color.LTGRAY)
                textSize = 13f
                gravity = Gravity.CENTER
                setPadding(32, 24, 32, 0)
            }
            addView(tvTitle)
            addView(tvSub)
        }

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        try {
            wm.addView(container, lp)
            view = container
        } catch (_: Exception) { return }

        // Panggil langsung BringToFront saat overlay muncul
        BringToFront.run(app)

        main.postDelayed({ hide(app) }, 4000)
    }

    fun hide(ctx: Context) {
        val v = view ?: return
        view = null
        main.removeCallbacksAndMessages(null)
        try {
            ctx.applicationContext.getSystemService(WindowManager::class.java)?.removeView(v)
        } catch (_: Exception) {}
    }
}
