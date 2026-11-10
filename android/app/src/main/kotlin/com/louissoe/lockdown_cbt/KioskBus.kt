package com.louissoe.lockdown_cbt

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object KioskBus {
    @Volatile var sink: EventChannel.EventSink? = null
    private var last: Map<String, Any?>? = null
    private val main = Handler(Looper.getMainLooper())

    fun reset() { last = null }

    fun emit(status: Map<String, Any?>) {
        if (status == last) return
        last = status
        main.post { sink?.success(status) }
    }
}
