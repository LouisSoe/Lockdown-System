package com.louissoe.lockdown_cbt

import android.content.Context
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.Executors

object EventQueue {
    private const val TAG = "ExamKiosk"
    private const val PREF = "exam_events"
    private const val KEY = "queue"
    private const val MAX = 500

    private val lock = Any()
    private val io = Executors.newSingleThreadExecutor()
    private val lastByKey = HashMap<String, Long>()
    private var app: Context? = null

    fun init(ctx: Context) { app = ctx.applicationContext }

    fun enqueue(type: String, detail: String = "", dedupeMs: Long = 0) {
        val ctx = app ?: return
        val now = System.currentTimeMillis()
        if (dedupeMs > 0) {
            val key = "$type|$detail"
            synchronized(lock) {
                if (now - (lastByKey[key] ?: 0L) < dedupeMs) return
                lastByKey[key] = now
            }
        }
        val o = JSONObject()
            .put("event_id", UUID.randomUUID().toString())
            .put("exam_id", ExamSession.examId)
            .put("student_id", ExamSession.studentId)
            .put("type", type)
            .put("detail", detail)
            .put("client_ts", now)
            .put("device", device())
        Log.i(TAG, "event $type $detail")
        synchronized(lock) {
            val arr = load(ctx)
            arr.put(o)
            save(ctx, trim(arr))
        }
        flush()
    }

    fun flush() {
        io.execute {
            val ctx = app ?: return@execute
            if (ExamSession.apiBase.isEmpty()) return@execute
            val snapshot = synchronized(lock) { load(ctx) }
            val sent = HashSet<String>()
            for (i in 0 until snapshot.length()) {
                val o = snapshot.getJSONObject(i)
                if (!post("/api/exam/events", o)) break
                sent.add(o.getString("event_id"))
            }
            if (sent.isEmpty()) return@execute
            synchronized(lock) {
                val cur = load(ctx)
                val rest = JSONArray()
                for (i in 0 until cur.length()) {
                    val o = cur.getJSONObject(i)
                    if (o.getString("event_id") !in sent) rest.put(o)
                }
                save(ctx, rest)
            }
        }
    }

    fun heartbeat(status: Map<String, Any?>) {
        io.execute {
            val o = JSONObject()
                .put("exam_id", ExamSession.examId)
                .put("student_id", ExamSession.studentId)
                .put("client_ts", System.currentTimeMillis())
                .put("state", status["state"])
                .put("violations", status["violations"])
                .put("status", JSONObject(status))
                .put("device", device())
            post("/api/exam/heartbeat", o)
        }
        flush()
    }

    private fun device() = JSONObject()
        .put("sdk", Build.VERSION.SDK_INT)
        .put("brand", Build.MANUFACTURER)
        .put("model", Build.MODEL)

    private fun trim(arr: JSONArray): JSONArray {
        if (arr.length() <= MAX) return arr
        val out = JSONArray()
        for (i in arr.length() - MAX until arr.length()) out.put(arr.get(i))
        return out
    }

    private fun load(ctx: Context): JSONArray = try {
        JSONArray(ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString(KEY, "[]"))
    } catch (e: Exception) { JSONArray() }

    private fun save(ctx: Context, arr: JSONArray) {
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit().putString(KEY, arr.toString()).apply()
    }

    // 2xx = terkirim. 4xx (selain 401/403/408/429) = event ditolak permanen, dibuang agar antrean tidak macet.
    private fun post(path: String, body: JSONObject): Boolean = try {
        val base = ExamSession.apiBase.trimEnd('/')
        val effectivePath = if (base.endsWith("/api") && path.startsWith("/api")) {
            path.removePrefix("/api")
        } else {
            path
        }
        val c = URL(base + effectivePath).openConnection() as HttpURLConnection
        c.requestMethod = "POST"
        c.connectTimeout = 4000
        c.readTimeout = 4000
        c.doOutput = true
        c.setRequestProperty("Content-Type", "application/json; charset=utf-8")
        if (ExamSession.token.isNotEmpty()) {
            c.setRequestProperty("Authorization", "Bearer ${ExamSession.token}")
        }
        c.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
        val code = c.responseCode
        c.disconnect()
        code in 200..299 || (code in 400..499 && code !in setOf(401, 403, 408, 429))
    } catch (e: Exception) { false }
}
