# Kiosk Ujian Berlapis Flutter (Android 8–16)

Oct 26, 2026 · @Lou

## Ringkasan

Dokumen ini memberi cetak biru, kode, dan checklist uji untuk kiosk ujian berlapis di Flutter, Android 8 sampai 16 (API 26–36), dengan satu logika ujian untuk semua versi. Tidak ada cabang "jika Android 11" di sisi ujian: semua lapisan dicoba di semua perangkat, statusnya dilaporkan ke server, dan soal hanya tampil bila semua lapisan wajib aktif.

Yang dijamin: soal disembunyikan dalam kira-kira satu detik saat syarat tidak terpenuhi, setiap pelanggaran tercatat di server lengkap dengan durasi, dan siswa yang mematikan perlindungan atau menutup aplikasi terdeteksi lewat heartbeat. Yang tidak dijamin tanpa Device Owner: mencegah aplikasi lain tampil sekejap, dan pin ulang tanpa dialog konfirmasi sistem.

| Permintaan Anda | Cara dipenuhi | Bagian |
| --- | --- | --- |
| Keluar aplikasi saat ujian dilaporkan ke admin lewat API | Event `GATE_CLOSED` dan `FOREIGN_APP`, dikirim dari foreground service lewat antrean persisten | 5, 7 |
| Setelah keluar, langsung kembali ke aplikasi ujian | `startActivity` + `moveTaskToFront` dari AccessibilityService dan service, ditutup overlay hitam | 5 |
| Pin ulang otomatis | Percobaan otomatis terbatas + tombol manual; dialog sistem tetap muncul tanpa Device Owner | 5, 6, 8 |
| Buka aplikasi lain justru membuka aplikasi ujian | Deteksi aplikasi asing (aksesibilitas + UsageStats), overlay, tarik balik; aplikasi ujian jadi launcher Home selama ujian | 5 |
| Perilaku sama di Android 8, 11, dan 16 | Lapisan sama di semua versi, status tiap lapisan dilaporkan, soal ditutup bila lapisan wajib mati | 2, 6 |

Bagian dirujuk menurut urutannya: 1 Ringkasan, 2 Arsitektur, 3 Prasyarat, 4 Konfigurasi, 5 Kode Kotlin, 6 Kode Flutter, 7 Kontrak API, 8 Device Owner, 9 Pengujian, 10 Asumsi. Cara memakai dokumen: kerjakan bagian 3 sampai 6 berurutan di proyek Flutter Anda, sambungkan server sesuai bagian 7, lalu jalankan matriks uji di bagian 9. Bagian 10 memuat daftar asumsi yang harus Anda verifikasi di perangkat nyata sebelum dipakai ujian sungguhan.

## Arsitektur

Perlindungan dibagi delapan lapisan. Tidak ada satu lapisan yang dipercaya sendirian: L1 bisa dilepas siswa, L3 bisa dimatikan, L5 bisa diblokir OEM. Yang menjaga hasilnya tetap sama adalah L6 (gerbang konten) dan L7 (server).

| Lapisan | Fungsi | Komponen kode | Status |
| --- | --- | --- | --- |
| L0 Device Owner | Lock task penuh tanpa dialog, bila perangkat disediakan sekolah | `LockdownAdminReceiver`, bagian 8 | Opsional |
| L1 Screen pinning | Penghalang dasar Home, Recents, notifikasi | `MainActivity.requestPin()` | Wajib |
| L2 Launcher Home sementara | Tombol Home selalu membuka aplikasi ujian | `ExamHomeAlias` | Disarankan |
| L3 AccessibilityService | Mendeteksi aplikasi asing, menutup notifikasi, menarik balik | `ExamGuardService` | Wajib |
| L4 UsageStats | Cadangan deteksi aplikasi di depan | `ForegroundDetector` | Disarankan |
| L5 Overlay dan tarik balik | Menutup aplikasi asing, membawa aplikasi ujian ke depan | `OverlayBlocker`, `BringToFront` | Wajib |
| L6 Gerbang konten | Soal hanya tampil bila semua lapisan wajib aktif | `KioskStatus`, `ExamGate` | Wajib |
| L7 Server | Heartbeat, log pelanggaran, kebijakan auto-submit | `EventQueue`, API | Wajib |

&#91;embedded content: arsitektur kiosk · Flutter, native, server\]

Dart tidak menghitung pelanggaran: ia menerima status dari `ExamForegroundService` dan menyembunyikan soal saat `gateOpen` bernilai `false`.

### State ujian

Satu state machine untuk semua versi Android. Native menghitungnya setiap 500 ms, Dart hanya menampilkan.

1. **PREFLIGHT**: ujian belum dimulai, prasyarat diperiksa di wizard.
2. **AMAN**: pin aktif, jendela punya fokus, bukan multi-window, tidak ada aplikasi asing di depan, dan prasyarat (aksesibilitas, overlay, baterai, notifikasi) aktif. Soal tampil.
3. **PELANGGARAN**: salah satu syarat gugur. Soal disembunyikan, event `GATE_CLOSED` dikirim, aplikasi ditarik ke depan, pin diminta ulang. Saat syarat pulih, event `GATE_OPENED` membawa durasi keluar.

Selama 15 detik pertama setelah ujian dimulai (masa tenggang untuk dialog pin), gerbang tetap tertutup tetapi pelanggaran tidak dihitung. Watchdog berjalan tiap 500 ms, heartbeat ke server tiap 5 detik, dan server menandai siswa hilang bila tidak ada heartbeat selama 20 detik.

## Prasyarat dan struktur proyek

**Prasyarat**

- Flutter 3.24 atau lebih baru (butuh `PopScope` dan dukungan predictive back).
- `minSdk = 26`. Karena batas bawah Android 8, kode tidak perlu cabang untuk API di bawah 26.
- `compileSdk` 35 atau lebih tinggi, Android Gradle Plugin dan Kotlin versi yang cocok dengan Flutter Anda.
- Perangkat uji nyata. Emulator tidak cukup untuk perilaku OEM, aksesibilitas, dan overlay.
- Server HTTPS. Android 9 ke atas memblokir HTTP polos secara default.

**Nama paket.** Semua contoh memakai `com.example.examkiosk`. Ganti dengan `namespace` di `android/app/build.gradle` Anda, termasuk baris `package` di setiap file Kotlin dan nama komponen di manifest.

**Integrasi dengan kode yang sudah ada.** Anda sudah punya `LockdownPlugin.kt`, `MainActivity.kt`, dan `AntiCheatPlugin.kt`. Cara paling aman:

- Pertahankan yang sudah stabil lintas versi: `FLAG_SECURE`, `FLAG_KEEP_SCREEN_ON`, dan pembersih clipboard.
- Hapus atau matikan yang rapuh: reflection `collapsePanels()`, broadcast `ACTION_CLOSE_SYSTEM_DIALOGS` dari plugin, `moveTaskToFront` yang tersebar, dan `onBackPressed()`. Semuanya digantikan komponen baru di bawah.
- Jangan menjalankan dua pengelola pin sekaligus. Satu-satunya pemanggil `startLockTask()` adalah `MainActivity.requestPin()` di bagian 5.
- Bila `MainActivity` Anda sudah punya `MethodChannel` lain, gabungkan `when` di bagian 5 ke handler yang ada, jangan membuat dua handler untuk channel yang sama.

**Struktur berkas**

```text
android/app/src/main/
  AndroidManifest.xml
  kotlin/com/example/examkiosk/
    MainActivity.kt
    ExamSession.kt
    KioskStatus.kt
    KioskBus.kt
    EventQueue.kt
    Allowlist.kt
    ForegroundDetector.kt
    BringToFront.kt
    OverlayBlocker.kt
    ExamGuardService.kt
    ExamForegroundService.kt
    LockdownAdminReceiver.kt      (hanya untuk Device Owner)
  res/xml/
    exam_guard_config.xml
    device_admin.xml              (hanya untuk Device Owner)
  res/values/strings.xml
lib/
  kiosk/
    kiosk_controller.dart
    preflight_page.dart
    exam_gate.dart
  main.dart
```

## Konfigurasi

Tidak ada paket Dart tambahan. Semua logika berat ada di Kotlin dan berkomunikasi lewat `MethodChannel` dan `EventChannel` bawaan Flutter.

### Gradle

Di `android/app/build.gradle.kts` (di Groovy: `minSdkVersion 26`, `compileSdkVersion 35`):

```kotlin
android {
    compileSdk = 35
    defaultConfig {
        minSdk = 26
        // targetSdk biasanya sudah diatur Flutter; uji pada target 35 dan 36
    }
}
```

### strings.xml

Tambahkan ke `res/values/strings.xml`:

```xml
<string name="guard_label">Penjaga Ujian</string>
<string name="guard_desc">Mendeteksi aplikasi lain yang dibuka selama ujian dan mengembalikan siswa ke aplikasi ujian. Layanan ini tidak membaca isi layar.</string>
```

### exam\_guard\_config.xml

Buat `res/xml/exam_guard_config.xml`. Izinnya sengaja dibuat sekecil mungkin: hanya perubahan jendela, tanpa membaca isi layar.

```xml
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:canRetrieveWindowContent="false"
    android:notificationTimeout="50"
    android:description="@string/guard_desc" />
```

### AndroidManifest.xml

Tambahkan izin dan komponen berikut. Atribut `<activity>` yang sudah dibuat template Flutter (misalnya `configChanges`, `theme`, `hardwareAccelerated`) dipertahankan, hanya empat atribut yang ditambah atau diubah. Izin `INTERNET` wajib ada di manifest utama, bukan hanya di manifest debug.

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.REORDER_TASKS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    <uses-permission android:name="android.permission.PACKAGE_USAGE_STATS"
        tools:ignore="ProtectedPermissions" />

    <!-- Android 11+: agar resolveActivity() untuk Home tidak difilter -->
    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.HOME" />
        </intent>
    </queries>

    <application
        android:enableOnBackInvokedCallback="true"
        ... >

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTask"
            android:resizeableActivity="false"
            android:supportsPictureInPicture="false"
            ... >
            <!-- intent-filter MAIN/LAUNCHER bawaan Flutter tetap -->
        </activity>

        <!-- L2: dinyalakan hanya selama ujian lewat PackageManager -->
        <activity-alias
            android:name=".ExamHomeAlias"
            android:targetActivity=".MainActivity"
            android:enabled="false"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.HOME" />
                <category android:name="android.intent.category.DEFAULT" />
            </intent-filter>
        </activity-alias>

        <service
            android:name=".ExamForegroundService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="exam_kiosk_monitoring" />
        </service>

        <service
            android:name=".ExamGuardService"
            android:exported="true"
            android:label="@string/guard_label"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/exam_guard_config" />
        </service>
    </application>
</manifest>
```

Catatan konfigurasi:

- `resizeableActivity="false"` tidak cukup di semua versi (lihat bagian 10). Deteksi multi-window di kode tetap wajib.
- `foregroundServiceType="specialUse"` dibutuhkan di Android 14 ke atas. Untuk distribusi di Play Store, jenis ini butuh deklarasi; untuk APK internal tidak masalah.
- `PACKAGE_USAGE_STATS` dan `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` bukan izin yang muncul di dialog biasa. Siswa mengaktifkannya lewat layar Pengaturan, dibuka oleh wizard di bagian 6.

## Kode Kotlin

Semua berkas ada di `android/app/src/main/kotlin/com/example/examkiosk/`. Urutannya mengikuti ketergantungan: state bersama, pelapor event, lalu detektor, service, dan terakhir `MainActivity`. Tahap pertama ini berisi lima berkas dasar.

### ExamSession.kt

Satu-satunya tempat state bersama. Semua properti `@Volatile` karena dibaca dari beberapa thread (main, aksesibilitas, executor jaringan).

```kotlin
package com.example.examkiosk

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

    @Volatile var violations = 0
    @Volatile var graceUntil = 0L
    @Volatile var pinningUntil = 0L

    fun now(): Long = SystemClock.elapsedRealtime()
    fun inGrace() = now() < graceUntil
    fun pinningInProgress() = now() < pinningUntil
    fun markPinning(ms: Long = 10_000) { pinningUntil = now() + ms }
}
```

### KioskStatus.kt

Menghitung snapshot status. Fungsi ini satu-satunya sumber kebenaran untuk gerbang konten, dipanggil oleh watchdog dan oleh `getStatus`.

```kotlin
package com.example.examkiosk

import android.Manifest
import android.app.ActivityManager
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings

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

    fun snapshot(ctx: Context): Map<String, Any?> {
        val guard = ExamGuardService.connected
        val overlay = Settings.canDrawOverlays(ctx)
        val battery = ctx.getSystemService(PowerManager::class.java)
            .isIgnoringBatteryOptimizations(ctx.packageName)
        val notif = Build.VERSION.SDK_INT < 33 ||
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val pinned = isPinned(ctx)
        val focus = ExamSession.hasFocus || ExamSession.pinningInProgress()
        val single = !ExamSession.multiWindow
        val clear = ExamSession.foreignPkg == null

        val missing = buildList {
            if (!guard) add("guard")
            if (!overlay) add("overlay")
            if (!battery) add("battery")
            if (!notif) add("notif")
            if (ExamSession.active) {
                if (!pinned) add("pinned")
                if (!focus) add("focus")
                if (!single) add("singleWindow")
                if (!clear) add("foreignApp")
            }
        }
        val gateOpen = ExamSession.active && missing.isEmpty()
        val state = when {
            !ExamSession.active -> "PREFLIGHT"
            gateOpen -> "AMAN"
            else -> "PELANGGARAN"
        }
        return mapOf(
            "state" to state,
            "gateOpen" to gateOpen,
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
```

Prasyarat wajib (`prereqOk`): aksesibilitas, overlay, optimasi baterai, notifikasi. Usage access dan launcher Home sengaja tidak wajib: keduanya penguat, bukan syarat jalan. Bila Anda ingin ketat, tambahkan `usage` dan `home` ke daftar `missing`.

### KioskBus.kt

Jembatan status ke Flutter lewat `EventChannel`. Status hanya dikirim bila berubah.

```kotlin
package com.example.examkiosk

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
```

### Allowlist.kt

Daftar paket yang boleh tampil selama ujian: aplikasi sendiri, System UI, keyboard yang aktif, dan paket tambahan dari Dart. Dialog izin dan pengaturan tidak masuk daftar: semuanya harus selesai di wizard sebelum ujian dimulai.

```kotlin
package com.example.examkiosk

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
            .enabledInputMethodList.map { it.packageName }.toSet()
}
```

### EventQueue.kt

Antrean event persisten (SharedPreferences) dengan pengiriman ulang. Event baru bisa dikirim ulang tanpa duplikat karena setiap event punya `event_id` UUID yang harus diperlakukan idempoten oleh server. Heartbeat tidak diantrikan, karena heartbeat basi tidak berguna.

```kotlin
package com.example.examkiosk

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
        val c = URL(ExamSession.apiBase.trimEnd('/') + path).openConnection() as HttpURLConnection
        c.requestMethod = "POST"
        c.connectTimeout = 4000
        c.readTimeout = 4000
        c.doOutput = true
        c.setRequestProperty("Content-Type", "application/json; charset=utf-8")
        c.setRequestProperty("Authorization", "Bearer ${ExamSession.token}")
        c.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
        val code = c.responseCode
        c.disconnect()
        code in 200..299 || (code in 400..499 && code !in setOf(401, 403, 408, 429))
    } catch (e: Exception) { false }
}
```

Catatan: `ExamSession.apiBase` dan `token` sengaja tidak dikosongkan saat ujian berhenti, supaya event `EXAM_ENDED` yang terakhir masih terkirim. Keduanya ditimpa pada `startExam` berikutnya.

### ForegroundDetector.kt (L4)

Cadangan bila layanan aksesibilitas dimatikan atau terlambat. Membaca event UsageStats sejak polling terakhir dan mengingat paket yang terakhir muncul di depan.

```kotlin
package com.example.examkiosk

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build

class ForegroundDetector(ctx: Context) {
    private val usm = ctx.getSystemService(UsageStatsManager::class.java)
    private var since = System.currentTimeMillis() - 3000
    private var current: String? = null

    @Suppress("DEPRECATION")
    private val resumed =
        if (Build.VERSION.SDK_INT >= 29) UsageEvents.Event.ACTIVITY_RESUMED
        else UsageEvents.Event.MOVE_TO_FOREGROUND

    fun poll(): String? {
        val now = System.currentTimeMillis()
        val events = usm.queryEvents(since, now)
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType == resumed) current = e.packageName
        }
        since = now - 300   // tumpang tindih kecil agar tidak ada event terlewat
        return current
    }
}
```

### BringToFront.kt (L5)

Mencoba dua jalur sekaligus: `startActivity` dengan flag reorder, lalu `moveTaskToFront`. Android 10 ke atas dapat memblokir `startActivity` dari background tanpa melempar exception, hanya menulis log. Karena itu keberhasilan tidak diasumsikan: service memeriksa `lastResumeAt` dua detik kemudian dan mengirim event `BRING_FRONT_FAILED` bila gagal.

```kotlin
package com.example.examkiosk

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.SystemClock

object BringToFront {
    private var last = 0L

    fun run(ctx: Context) {
        val now = SystemClock.elapsedRealtime()
        if (now - last < 600) return
        last = now
        val app = ctx.applicationContext
        try {
            app.startActivity(
                Intent(app, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            )
        } catch (_: Exception) {}
        try {
            if (ExamSession.taskId >= 0) {
                app.getSystemService(ActivityManager::class.java)
                    .moveTaskToFront(ExamSession.taskId, ActivityManager.MOVE_TASK_WITH_HOME)
            }
        } catch (_: Exception) {}
    }
}
```

### OverlayBlocker.kt (L5)

Layar hitam penuh di atas aplikasi asing, memakai izin `SYSTEM_ALERT_WINDOW`. Menyembunyikan diri otomatis setelah 4 detik, atau segera saat aplikasi ujian kembali berfokus. Bila aplikasi asing masih di depan, watchdog menampilkannya lagi.

```kotlin
package com.example.examkiosk

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.TextView

object OverlayBlocker {
    private var view: View? = null
    private val main = Handler(Looper.getMainLooper())

    fun show(ctx: Context) {
        if (view != null || !Settings.canDrawOverlays(ctx)) return
        val app = ctx.applicationContext
        val wm = app.getSystemService(WindowManager::class.java)
        val v = TextView(app).apply {
            text = "Kembali ke aplikasi ujian..."
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setBackgroundColor(Color.BLACK)
            isClickable = true
        }
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        try {
            wm.addView(v, lp)
            view = v
        } catch (_: Exception) { return }
        main.postDelayed({ hide(app) }, 4000)
    }

    fun hide(ctx: Context) {
        val v = view ?: return
        view = null
        main.removeCallbacksAndMessages(null)
        try {
            ctx.applicationContext.getSystemService(WindowManager::class.java).removeView(v)
        } catch (_: Exception) {}
    }
}
```

### ExamGuardService.kt (L3)

Inti deteksi aplikasi asing. Setiap perubahan jendela dari paket yang tidak ada di allowlist langsung dilaporkan, ditutup overlay, dan aplikasi ujian ditarik ke depan. Event dari System UI hanya memicu penutupan notifikasi, kecuali saat dialog pin sedang tampil (di Android 11 ke bawah, menutup dialog sistem akan ikut menutup dialog pin).

```kotlin
package com.example.examkiosk

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent

class ExamGuardService : AccessibilityService() {

    companion object {
        @Volatile var connected = false
    }

    private var lastShadeAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        connected = true
        EventQueue.init(applicationContext)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        connected = false
        if (ExamSession.active) EventQueue.enqueue("GUARD_DISABLED")
        return super.onUnbind(intent)
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(e: AccessibilityEvent) {
        if (!ExamSession.active || e.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = e.packageName?.toString() ?: return

        if (pkg == packageName) {
            ExamSession.foreignPkg = null
            OverlayBlocker.hide(this)
            return
        }
        if (Allowlist.isSystemUi(pkg)) {
            if (!ExamSession.pinningInProgress()) closeShade()
            return
        }
        if (Allowlist.isAllowed(this, pkg) || ExamSession.pinningInProgress()) return

        ExamSession.foreignPkg = pkg
        EventQueue.enqueue("FOREIGN_APP", pkg, dedupeMs = 1500)
        OverlayBlocker.show(this)
        closeShade()
        BringToFront.run(this)
    }

    @Suppress("DEPRECATION")
    private fun closeShade() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastShadeAt < 300) return
        lastShadeAt = now
        try {
            if (Build.VERSION.SDK_INT >= 31)
                performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
            else
                sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))
        } catch (_: Exception) {}
    }
}
```

Percabangan `SDK_INT >= 31` hanya memilih cara menutup notifikasi, di dalam satu fungsi. Logika ujian di luar fungsi ini tidak bercabang.

### ExamForegroundService.kt (watchdog dan heartbeat)

Service ini menjaga proses tetap hidup selama ujian, lalu tiap 500 ms menghitung status, menghitung pelanggaran, menarik aplikasi kembali bila perlu, dan tiap 5 detik mengirim heartbeat. Pelanggaran dihitung sekali per periode gerbang tertutup, bukan sekali per tick.

```kotlin
package com.example.examkiosk

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

class ExamForegroundService : Service() {

    private val h = Handler(Looper.getMainLooper())
    private var detector: ForegroundDetector? = null
    private var tick = 0
    private var closeReported = false
    private var closedAt = 0L
    private var lastBringAt = 0L

    private val loop = object : Runnable {
        override fun run() {
            if (!ExamSession.active) { stopSelf(); return }
            try { watchdog() } catch (e: Exception) { Log.e("ExamKiosk", "watchdog", e) }
            h.postDelayed(this, 500)
        }
    }

    override fun onBind(i: Intent?): IBinder? = null

    override fun onStartCommand(i: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        EventQueue.init(applicationContext)
        detector = if (KioskStatus.hasUsageAccess(this)) ForegroundDetector(this) else null
        closeReported = false
        tick = 0
        h.removeCallbacks(loop)
        h.post(loop)
        return START_NOT_STICKY   // bila proses mati, state sesi ikut hilang; Dart memulai ulang
    }

    override fun onDestroy() {
        h.removeCallbacksAndMessages(null)
        OverlayBlocker.hide(this)
        super.onDestroy()
    }

    private fun watchdog() {
        // L4: cadangan deteksi aplikasi di depan
        detector?.poll()?.let { fg ->
            if (fg == packageName) {
                ExamSession.foreignPkg = null
            } else if (!Allowlist.isAllowed(this, fg) && !ExamSession.pinningInProgress()) {
                if (ExamSession.foreignPkg != fg)
                    EventQueue.enqueue("FOREIGN_APP", fg, dedupeMs = 1500)
                ExamSession.foreignPkg = fg
            }
        }

        val s = KioskStatus.snapshot(this)
        val ok = s["gateOpen"] as Boolean
        val now = ExamSession.now()

        if (!ok) {
            if (!closeReported && !ExamSession.inGrace()) {
                closeReported = true
                closedAt = now
                ExamSession.violations++
                EventQueue.enqueue("GATE_CLOSED", (s["missing"] as List<*>).joinToString(","))
            }
            recover()
        } else if (closeReported) {
            closeReported = false
            EventQueue.enqueue("GATE_OPENED", "duration_ms=${now - closedAt}")
            OverlayBlocker.hide(this)
        }

        val out = s + mapOf("violations" to ExamSession.violations)
        KioskBus.emit(out)
        if (++tick % 10 == 0) EventQueue.heartbeat(out)   // 10 x 500 ms = 5 detik
    }

    // Aplikasi ujian ada di depan: cukup gerbang tertutup dan pin diminta ulang oleh MainActivity.
    // Aplikasi lain di depan: tutup dengan overlay dan tarik aplikasi ujian kembali.
    private fun recover() {
        if (ExamSession.pinningInProgress()) return
        val away = !ExamSession.hasFocus || ExamSession.foreignPkg != null
        if (!away) return
        OverlayBlocker.show(this)
        val now = ExamSession.now()
        if (now - lastBringAt >= 700) {
            lastBringAt = now
            BringToFront.run(this)
            h.postDelayed({
                if (ExamSession.active && ExamSession.lastResumeAt < now && ExamSession.foreignPkg != null)
                    EventQueue.enqueue("BRING_FRONT_FAILED", ExamSession.foreignPkg ?: "", dedupeMs = 10_000)
            }, 2000)
        }
    }

    private fun startInForeground() {
        val ch = "exam_guard"
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(ch, "Ujian berlangsung", NotificationManager.IMPORTANCE_LOW)
        )
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val n = Notification.Builder(this, ch)
            .setContentTitle("Ujian sedang berlangsung")
            .setContentText("Jangan menutup aplikasi ujian.")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setContentIntent(pi)
            .build()
        if (Build.VERSION.SDK_INT >= 34)
            startForeground(1001, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else
            startForeground(1001, n)
    }
}
```

### MainActivity.kt (L1, kanal ke Flutter)

Menggantikan `MainActivity` Anda. Bila sudah ada `MethodChannel` lain di sana, gabungkan ke `when` yang sama. `applyDeviceOwnerPolicy()` sengaja dikosongkan di sini dan diisi di bagian 8.

```kotlin
package com.example.examkiosk

import android.Manifest
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

    private var autoPinAt = 0L
    private var autoPinCount = 0
    private var notifAsked = false

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        EventQueue.init(applicationContext)
        val messenger = engine.dartExecutor.binaryMessenger

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
                "requestPin" -> { autoPinCount = 0; requestPin(); result.success(null) }
                "openSetting" -> { openSetting(call.argument<String>("name") ?: ""); result.success(null) }
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
            extraAllowed = (call.argument<List<String>>("allowedPackages") ?: emptyList()).toSet()
            violations = 0
            foreignPkg = null
            graceUntil = now() + 15_000
            taskId = this@MainActivity.taskId
            active = true
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )
        setHomeAlias(true)
        startForegroundService(Intent(this, ExamForegroundService::class.java))
        EventQueue.enqueue("EXAM_STARTED")
        applyDeviceOwnerPolicy()
        autoPinCount = 0
        requestPin()
    }

    private fun stopExam() {
        EventQueue.enqueue("EXAM_ENDED")
        ExamSession.active = false
        try { stopLockTask() } catch (_: Exception) {}
        window.clearFlags(
            WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )
        setHomeAlias(false)
        OverlayBlocker.hide(this)
        stopService(Intent(this, ExamForegroundService::class.java))
        KioskBus.emit(currentStatus())
    }

    private fun applyDeviceOwnerPolicy() { /* diisi di bagian 8 */ }

    // ---- pin (L1) ----

    private fun requestPin() {
        if (!ExamSession.active || KioskStatus.isPinned(this)) return
        ExamSession.markPinning()
        try {
            startLockTask()
        } catch (e: Exception) {
            EventQueue.enqueue("PIN_FAILED", e.message ?: "", dedupeMs = 5000)
        }
    }

    // Maksimal 3 percobaan otomatis, jarak minimal 5 detik. Setelah itu siswa harus menekan tombol.
    private fun autoPin() {
        if (KioskStatus.isPinned(this)) { autoPinCount = 0; return }
        val now = ExamSession.now()
        if (autoPinCount < 3 && now - autoPinAt > 5000 && !ExamSession.pinningInProgress()) {
            autoPinAt = now
            autoPinCount++
            requestPin()
        }
    }

    // ---- siklus activity ----

    override fun onResume() {
        super.onResume()
        ExamSession.lastResumeAt = ExamSession.now()
        ExamSession.foreignPkg = null
        updateWindowMode()
        if (ExamSession.active) autoPin()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        ExamSession.hasFocus = hasFocus
        updateWindowMode()
        if (hasFocus) {
            ExamSession.foreignPkg = null
            OverlayBlocker.hide(this)
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
        packageManager.setComponentEnabledSetting(
            cn,
            if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP
        )
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
```

Catatan perilaku: `FLAG_SECURE` dan `FLAG_KEEP_SCREEN_ON` hanya dipasang selama ujian. Bila `LockdownPlugin` lama Anda memasangnya secara permanen, hapus salah satunya agar tidak saling menimpa. Jika `onDestroy` terpanggil saat ujian aktif (misalnya sistem mematikan activity), service akan menarik aplikasi kembali dan Flutter membuat engine baru, sehingga state Dart hilang. Karena itu jawaban siswa harus disimpan ke server atau penyimpanan lokal, bukan hanya di memori.

## Kode Flutter

Sisi Dart sengaja tipis: tidak ada logika pelanggaran di sini. Native yang menghitung status, Dart hanya menampilkan wizard persiapan dan menyembunyikan soal saat `gateOpen` bernilai `false`. Tidak ada paket tambahan di `pubspec.yaml`.

### lib/kiosk/kiosk\_controller.dart

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class KioskStatus {
  const KioskStatus(this.raw);
  final Map<String, dynamic> raw;

  static const empty = KioskStatus({});

  bool flag(String key) => raw[key] == true;
  bool get gateOpen => flag('gateOpen');
  bool get prereqOk => flag('prereqOk');
  String get state => (raw['state'] as String?) ?? 'PREFLIGHT';
  int get violations => (raw['violations'] as int?) ?? 0;
  List<String> get missing =>
      List<String>.from((raw['missing'] as List?) ?? const []);
}

enum KioskSetting { guard, overlay, battery, usage, home, notif, app }

class KioskController extends ChangeNotifier with WidgetsBindingObserver {
  KioskController() {
    WidgetsBinding.instance.addObserver(this);
    _sub = _events.receiveBroadcastStream().listen(_onStatus, onError: (_) {});
    refresh();
  }

  static const _method = MethodChannel('exam_kiosk/native');
  static const _events = EventChannel('exam_kiosk/events');

  StreamSubscription<dynamic>? _sub;
  KioskStatus status = KioskStatus.empty;
  bool _examActive = false;

  void _onStatus(dynamic data) {
    status = KioskStatus(Map<String, dynamic>.from(data as Map));
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      final data = await _method.invokeMethod<Map<dynamic, dynamic>>('getStatus');
      if (data != null) _onStatus(data);
    } on MissingPluginException {
      // bukan Android: status tetap kosong, gerbang tertutup
    }
  }

  Future<void> start({
    required String apiBase,
    required String token,
    required String examId,
    required String studentId,
    List<String> allowedPackages = const [],
  }) async {
    await _method.invokeMethod('startExam', {
      'apiBase': apiBase,
      'token': token,
      'examId': examId,
      'studentId': studentId,
      'allowedPackages': allowedPackages,
    });
    _examActive = true;
    await _immersive();
  }

  Future<void> stop() async {
    _examActive = false;
    await _method.invokeMethod('stopExam');
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> requestPin() => _method.invokeMethod('requestPin');

  Future<void> openSetting(KioskSetting s) =>
      _method.invokeMethod('openSetting', {'name': s.name});

  Future<void> _immersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      if (_examActive) _immersive();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }
}
```

Mode layar penuh memakai `SystemChrome.immersiveSticky` dari Flutter, yang sudah menangani perbedaan API lama dan baru. Kode `systemUiVisibility` dan `WindowInsetsController` manual di plugin lama tidak diperlukan lagi.

### lib/kiosk/preflight\_page.dart

Wizard persiapan. Tombol "Mulai ujian" aktif hanya bila semua prasyarat wajib hijau. Status diperbarui otomatis saat siswa kembali dari layar Pengaturan.

```dart
import 'package:flutter/material.dart';

import 'kiosk_controller.dart';

class _Item {
  const _Item(this.key, this.title, this.required, this.setting);
  final String key;
  final String title;
  final bool required;
  final KioskSetting setting;
}

class PreflightPage extends StatelessWidget {
  const PreflightPage({super.key, required this.kiosk, required this.onReady});

  final KioskController kiosk;
  final VoidCallback onReady;

  static const _items = <_Item>[
    _Item('guard', 'Layanan aksesibilitas "Penjaga Ujian" aktif', true, KioskSetting.guard),
    _Item('overlay', 'Izin tampil di atas aplikasi lain', true, KioskSetting.overlay),
    _Item('battery', 'Optimasi baterai dimatikan untuk aplikasi ini', true, KioskSetting.battery),
    _Item('notif', 'Izin notifikasi', true, KioskSetting.notif),
    _Item('usage', 'Akses penggunaan aplikasi (cadangan deteksi)', false, KioskSetting.usage),
    _Item('home', 'Aplikasi ujian sebagai layar utama', false, KioskSetting.home),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: kiosk,
      builder: (context, _) {
        final s = kiosk.status;
        return Scaffold(
          appBar: AppBar(title: const Text('Persiapan ujian')),
          body: ListView(
            children: [
              for (final it in _items)
                ListTile(
                  leading: Icon(
                    s.flag(it.key)
                        ? Icons.check_circle
                        : (it.required ? Icons.cancel : Icons.warning_amber),
                    color: s.flag(it.key)
                        ? Colors.green
                        : (it.required ? Colors.red : Colors.orange),
                  ),
                  title: Text(it.title),
                  subtitle: Text(it.required ? 'Wajib' : 'Disarankan'),
                  trailing: s.flag(it.key)
                      ? null
                      : TextButton(
                          onPressed: () => kiosk.openSetting(it.setting),
                          child: const Text('Atur'),
                        ),
                ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Pada beberapa merek (Xiaomi, Oppo, Vivo, Samsung) aktifkan juga '
                  '"Mulai otomatis" dan "Tanpa batasan baterai" di pengaturan aplikasi.',
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: s.prereqOk ? onReady : null,
                child: const Text('Mulai ujian'),
              ),
            ),
          ),
        );
      },
    );
  }
}
```

### lib/kiosk/exam\_gate.dart

Gerbang konten (L6). Soal tetap berada di tree widget (timer dan jawaban tidak hilang), tetapi tidak digambar dan tidak bisa disentuh saat gerbang tertutup. Selama ujian tidak ada tombol menuju Pengaturan: membukanya akan terdeteksi sebagai aplikasi asing. Satu-satunya aksi siswa adalah meminta pin ulang.

```dart
import 'package:flutter/material.dart';

import 'kiosk_controller.dart';

class ExamGate extends StatelessWidget {
  const ExamGate({super.key, required this.kiosk, required this.child});

  final KioskController kiosk;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: kiosk,
      builder: (context, _) {
        final open = kiosk.status.gateOpen;
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(offstage: !open, child: child),
            if (!open) _BlockedView(kiosk: kiosk),
          ],
        );
      },
    );
  }
}

const _labels = <String, String>{
  'guard': 'Layanan Penjaga Ujian mati',
  'overlay': 'Izin tampil di atas aplikasi lain dicabut',
  'battery': 'Optimasi baterai aktif kembali',
  'notif': 'Izin notifikasi dicabut',
  'pinned': 'Penyematan layar (pin) tidak aktif',
  'focus': 'Aplikasi ujian tidak berada di depan',
  'singleWindow': 'Layar terbagi atau jendela mengambang aktif',
  'foreignApp': 'Aplikasi lain terdeteksi di depan',
};

class _BlockedView extends StatelessWidget {
  const _BlockedView({required this.kiosk});
  final KioskController kiosk;

  @override
  Widget build(BuildContext context) {
    final s = kiosk.status;
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock, color: Colors.white, size: 48),
              const SizedBox(height: 16),
              const Text('Ujian dijeda',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 22)),
              const SizedBox(height: 16),
              for (final k in s.missing)
                Text(_labels[k] ?? k,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              Text('Pelanggaran tercatat: ${s.violations}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 24),
              if (s.missing.contains('pinned'))
                FilledButton(
                  onPressed: kiosk.requestPin,
                  child: const Text('Aktifkan pin'),
                ),
              const SizedBox(height: 12),
              const Text('Waktu ujian tetap berjalan. Hubungi pengawas bila masalah berlanjut.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}
```

### lib/main.dart (contoh perangkaian)

Ganti `apiBase`, `token`, `examId`, dan `studentId` dengan data login Anda. Halaman ujian dibungkus `PopScope(canPop: false)` supaya tombol dan gestur Back diabaikan di semua versi, termasuk predictive back di Android 13 ke atas (butuh `enableOnBackInvokedCallback` di manifest, sudah ada di bagian 4).

```dart
import 'package:flutter/material.dart';

import 'kiosk/exam_gate.dart';
import 'kiosk/kiosk_controller.dart';
import 'kiosk/preflight_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExamApp());
}

class ExamApp extends StatefulWidget {
  const ExamApp({super.key});
  @override
  State<ExamApp> createState() => _ExamAppState();
}

class _ExamAppState extends State<ExamApp> {
  final kiosk = KioskController();

  @override
  void dispose() {
    kiosk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (ctx) => PreflightPage(
          kiosk: kiosk,
          onReady: () async {
            await kiosk.start(
              apiBase: 'https://api.contoh.sch.id',
              token: 'TOKEN_SESI_SISWA',
              examId: 'EXAM-001',
              studentId: 'STD-001',
            );
            if (!ctx.mounted) return;
            Navigator.of(ctx).pushReplacement(
              MaterialPageRoute(builder: (_) => ExamPage(kiosk: kiosk)),
            );
          },
        ),
      ),
    );
  }
}

class ExamPage extends StatelessWidget {
  const ExamPage({super.key, required this.kiosk});
  final KioskController kiosk;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: ExamGate(
        kiosk: kiosk,
        child: Scaffold(
          appBar: AppBar(title: const Text('Ujian'), automaticallyImplyLeading: false),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Soal ujian tampil di sini'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await kiosk.stop();
                    if (!context.mounted) return;
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(
                          body: Center(child: Text('Ujian selesai')),
                        ),
                      ),
                    );
                  },
                  child: const Text('Selesaikan ujian'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

## Kontrak API server

Server adalah penentu akhir: klien hanya melapor, server yang memutuskan sanksi. Semua request memakai `Authorization: Bearer <token sesi siswa>` dan HTTPS. Server wajib memeriksa bahwa `student_id` di body sama dengan pemilik token.

### POST /api/exam/events

Satu event per request. Server harus **idempoten pada `event_id`**: event yang sama bisa datang lebih dari sekali karena antrean mengirim ulang. Balas 200 untuk duplikat, jangan 409, karena klien memperlakukan kode 401, 403, 408, 429, dan 5xx sebagai "coba lagi" dan 4xx lain sebagai "buang".

```json
{
  "event_id": "3f2a9c1e-5b7d-4e8a-9c21-7d4e5f6a8b90",
  "exam_id": "EXAM-001",
  "student_id": "STD-001",
  "type": "GATE_CLOSED",
  "detail": "pinned,focus",
  "client_ts": 1793000000000,
  "device": { "sdk": 34, "brand": "samsung", "model": "SM-A155F" }
}
```

| Type | Dikirim saat | Isi `detail` |
| --- | --- | --- |
| `EXAM_STARTED` | `startExam` dipanggil | kosong |
| `EXAM_ENDED` | `stopExam` dipanggil | kosong |
| `GATE_CLOSED` | Gerbang tertutup di luar masa tenggang | daftar `missing`, dipisah koma |
| `GATE_OPENED` | Gerbang pulih | `duration_ms=<n>` |
| `FOREIGN_APP` | Aplikasi di luar allowlist tampil | nama paket |
| `USER_LEAVE_HINT` | Siswa menekan Home atau Recents | kosong |
| `BRING_FRONT_FAILED` | Tarik balik tidak berhasil dalam 2 detik | nama paket asing |
| `PIN_FAILED` | `startLockTask()` melempar exception | pesan error |
| `GUARD_DISABLED` | Layanan aksesibilitas dilepas saat ujian | kosong |
| `ACTIVITY_DESTROYED` | Activity dihancurkan saat ujian | `finishing=true` atau `false` |

### POST /api/exam/heartbeat

Dikirim tiap 5 detik. Tidak diantrikan: bila gagal, heartbeat berikutnya yang menggantikan. Server menyimpan hanya yang terakhir per siswa.

```json
{
  "exam_id": "EXAM-001",
  "student_id": "STD-001",
  "client_ts": 1793000005000,
  "state": "AMAN",
  "violations": 1,
  "status": { "pinned": true, "guard": true, "overlay": true, "battery": true, "notif": true, "usage": true, "home": false, "focus": true, "singleWindow": true },
  "device": { "sdk": 34, "brand": "samsung", "model": "SM-A155F" }
}
```

### Kebijakan di sisi server

| Kondisi | Tindakan yang disarankan |
| --- | --- |
| Tidak ada heartbeat lebih dari 20 detik | Tandai siswa "hilang", tampilkan di dasbor pengawas |
| Heartbeat berisi `guard=false` atau `pinned=false` saat `state` = `AMAN` | Tandai anomali (status klien tidak konsisten) |
| `violations` mencapai batas (misalnya 3) | Kunci sesi sampai pengawas membuka, atau auto-submit sesuai kebijakan sekolah |
| `BRING_FRONT_FAILED` berulang pada perangkat yang sama | Tandai perangkat tidak kompatibel, sarankan Device Owner atau perangkat lain |
| Total durasi `GATE_OPENED` melebihi batas menit | Tandai untuk ditinjau |

Timer ujian harus dihitung di server dan terus berjalan selama pelanggaran, supaya keluar dari aplikasi tidak menambah waktu bagi siswa.

### Contoh implementasi Laravel (opsional)

Migrasi:

```php
Schema::create('exam_events', function (Blueprint $t) {
    $t->uuid('event_id')->primary();
    $t->string('exam_id')->index();
    $t->string('student_id')->index();
    $t->string('type', 40)->index();
    $t->string('detail', 255)->nullable();
    $t->unsignedBigInteger('client_ts');
    $t->json('device')->nullable();
    $t->timestamp('received_at')->useCurrent();
});

Schema::create('exam_heartbeats', function (Blueprint $t) {
    $t->id();
    $t->string('exam_id');
    $t->string('student_id');
    $t->string('state', 20);
    $t->unsignedInteger('violations')->default(0);
    $t->json('status')->nullable();
    $t->json('device')->nullable();
    $t->timestamp('last_seen_at')->index();
    $t->unique(['exam_id', 'student_id']);
});
```

Route dan controller:

```php
// routes/api.php
Route::middleware('auth:sanctum')->prefix('exam')->group(function () {
    Route::post('events', [ExamMonitorController::class, 'event']);
    Route::post('heartbeat', [ExamMonitorController::class, 'heartbeat']);
});

// app/Http/Controllers/ExamMonitorController.php
public function event(Request $r)
{
    $d = $r->validate([
        'event_id'   => 'required|uuid',
        'exam_id'    => 'required|string',
        'student_id' => 'required|string',
        'type'       => 'required|string|max:40',
        'detail'     => 'nullable|string|max:255',
        'client_ts'  => 'required|integer',
        'device'     => 'nullable|array',
    ]);
    // sesuaikan dengan model user Anda
    abort_unless($r->user()->student_id === $d['student_id'], 403);

    DB::table('exam_events')->insertOrIgnore([
        'event_id'    => $d['event_id'],
        'exam_id'     => $d['exam_id'],
        'student_id'  => $d['student_id'],
        'type'        => $d['type'],
        'detail'      => $d['detail'] ?? null,
        'client_ts'   => $d['client_ts'],
        'device'      => json_encode($d['device'] ?? null),
        'received_at' => now(),
    ]);
    return response()->json(['ok' => true]);
}

public function heartbeat(Request $r)
{
    $d = $r->validate([
        'exam_id'    => 'required|string',
        'student_id' => 'required|string',
        'state'      => 'required|string|max:20',
        'violations' => 'required|integer',
        'status'     => 'nullable|array',
        'device'     => 'nullable|array',
    ]);
    abort_unless($r->user()->student_id === $d['student_id'], 403);

    DB::table('exam_heartbeats')->upsert([[
        'exam_id'      => $d['exam_id'],
        'student_id'   => $d['student_id'],
        'state'        => $d['state'],
        'violations'   => $d['violations'],
        'status'       => json_encode($d['status'] ?? null),
        'device'       => json_encode($d['device'] ?? null),
        'last_seen_at' => now(),
    ]], ['exam_id', 'student_id'],
       ['state', 'violations', 'status', 'device', 'last_seen_at']);
    return response()->json(['ok' => true]);
}
```

Deteksi siswa hilang paling mudah dengan scheduler per menit: `exam_heartbeats` yang `last_seen_at` lebih dari 20 detik lalu dan ujiannya masih berjalan dicatat sebagai `HEARTBEAT_LOST` di `exam_events` oleh server sendiri.

## Device Owner (L0, opsional)

Bila sekolah menyediakan perangkat, jadikan aplikasi ini Device Owner. Lock task penuh berjalan tanpa dialog konfirmasi, tombol Home, Recents, dan notifikasi diblokir sistem, dan semua lapisan lain (L2 sampai L7) tetap aktif sebagai cadangan. Kode yang sudah ditulis tidak berubah: `isPinned()` membaca `lockTaskModeState`, yang bernilai `LOCKED` pada Device Owner dan `PINNED` pada pin biasa, dan keduanya dianggap aktif.

Perangkat siswa pribadi (BYOD) tidak bisa memakai jalur ini, karena Device Owner mengharuskan perangkat belum memiliki akun dan biasanya perlu reset pabrik.

### Receiver dan konfigurasi

`LockdownAdminReceiver.kt`:

```kotlin
package com.example.examkiosk

import android.app.admin.DeviceAdminReceiver

class LockdownAdminReceiver : DeviceAdminReceiver()
```

`res/xml/device_admin.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<device-admin xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-policies />
</device-admin>
```

Tambahkan di dalam `<application>` pada manifest:

```xml
<receiver
    android:name=".LockdownAdminReceiver"
    android:exported="true"
    android:permission="android.permission.BIND_DEVICE_ADMIN">
    <meta-data
        android:name="android.app.device_admin"
        android:resource="@xml/device_admin" />
    <intent-filter>
        <action android:name="android.app.action.DEVICE_ADMIN_ENABLED" />
    </intent-filter>
</receiver>
```

### Mengisi applyDeviceOwnerPolicy di MainActivity

Ganti fungsi kosong di bagian 5 dengan dua fungsi ini, dan panggil `releaseDeviceOwnerPolicy()` di dalam `stopExam()` setelah `stopLockTask()`. Tambahkan impor `android.app.admin.DevicePolicyManager`. Pelepasan wajib: tanpa itu status bar dan keyguard perangkat tetap terkunci setelah ujian selesai.

```kotlin
private fun applyDeviceOwnerPolicy() {
    val dpm = getSystemService(DevicePolicyManager::class.java)
    if (!dpm.isDeviceOwnerApp(packageName)) return
    val admin = ComponentName(this, LockdownAdminReceiver::class.java)
    try {
        dpm.setLockTaskPackages(admin, arrayOf(packageName))
        if (Build.VERSION.SDK_INT >= 28) dpm.setLockTaskFeatures(admin, 0)  // semua UI sistem mati
        dpm.setStatusBarDisabled(admin, true)
        dpm.setKeyguardDisabled(admin, true)   // mengembalikan false bila ada kunci layar aman
        dpm.setScreenCaptureDisabled(admin, true)
        EventQueue.enqueue("DEVICE_OWNER_ACTIVE")
    } catch (e: Exception) {
        EventQueue.enqueue("DEVICE_OWNER_FAILED", e.message ?: "")
    }
}

private fun releaseDeviceOwnerPolicy() {
    val dpm = getSystemService(DevicePolicyManager::class.java)
    if (!dpm.isDeviceOwnerApp(packageName)) return
    val admin = ComponentName(this, LockdownAdminReceiver::class.java)
    try {
        dpm.setStatusBarDisabled(admin, false)
        dpm.setKeyguardDisabled(admin, false)
        dpm.setScreenCaptureDisabled(admin, false)
    } catch (_: Exception) {}
}
```

Sebelum Android 9, lock task Device Owner sudah menyembunyikan seluruh UI sistem secara bawaan, dan `setLockTaskFeatures` baru ada di API 28. Pemeriksaan versi di atas hanya menjaga agar API itu tidak dipanggil di perangkat lama.

### Menjadikan aplikasi Device Owner

**Lewat ADB**, untuk jumlah perangkat kecil. Prasyarat: perangkat baru direset, belum ada akun (Google atau lainnya), dan USB debugging aktif. Beberapa merek (Xiaomi, Oppo) punya opsi tambahan "USB debugging (pengaturan keamanan)" yang harus diaktifkan.

```bash
adb install exam.apk
adb shell dpm set-device-owner com.example.examkiosk/.LockdownAdminReceiver
```

Hasil berhasil adalah pesan `Success`. Pesan yang paling sering muncul bila gagal adalah "already some accounts on the device": hapus semua akun atau reset pabrik.

**Lewat QR provisioning**, untuk banyak perangkat. Pada layar sambutan perangkat yang baru direset, ketuk layar enam kali lalu pindai QR berisi JSON berikut (Android 7 ke atas). APK harus bisa diunduh lewat HTTPS dari perangkat, jadi sertakan Wi-Fi bila perlu.

```json
{
  "android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME": "com.example.examkiosk/.LockdownAdminReceiver",
  "android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION": "https://contoh.sch.id/exam.apk",
  "android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_CHECKSUM": "<SHA-256 APK, base64 url-safe>",
  "android.app.extra.PROVISIONING_SKIP_ENCRYPTION": true,
  "android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED": true,
  "android.app.extra.PROVISIONING_WIFI_SSID": "NamaWiFi",
  "android.app.extra.PROVISIONING_WIFI_PASSWORD": "kata-sandi",
  "android.app.extra.PROVISIONING_WIFI_SECURITY_TYPE": "WPA"
}
```

Checksum dihitung dengan:

```bash
openssl dgst -binary -sha256 exam.apk | openssl base64 | tr '+/' '-_' | tr -d '='
```

**Zero-touch** (Android 8 ke atas) hanya untuk perangkat yang dibeli lewat reseller yang mendukungnya.

Untuk melepas Device Owner, aplikasi tidak bisa dihapus begitu saja. Cara termudah adalah reset pabrik. Siapkan juga SOP pelepasan sebelum perangkat dikembalikan atau dipindahtangankan.

### Verifikasi Device Owner aktif

Setelah `startExam`, cek di perangkat: event `DEVICE_OWNER_ACTIVE` muncul di server, tidak ada dialog pin, dan menahan Back dan Recents bersamaan (atau geser atas dan tahan pada navigasi gestur) tidak melepas penguncian. Bila dialog pin tetap muncul, aplikasi belum menjadi Device Owner.

## Pengujian dan verifikasi

Sebuah perangkat dinyatakan lulus bila skenario T01 sampai T16 di bawah menghasilkan perilaku di layar **dan** event yang sesuai di server. Uji di perangkat nyata; emulator tidak mewakili perilaku OEM, aksesibilitas, dan overlay.

### Perangkat minimum

Tes minimal satu perangkat per baris, ditambah satu perangkat per merek besar yang dipakai siswa Anda (Samsung, Xiaomi, Oppo atau Realme, Vivo) dan satu perangkat mendekati AOSP (misalnya Pixel) sebagai pembanding.

| Android | API | Alasan diuji |
| --- | --- | --- |
| 8.0 atau 8.1 | 26, 27 | Batas bawah dukungan, navigasi tiga tombol |
| 9 | 28 | Pembatasan hidden API mulai berlaku |
| 10 atau 11 | 29, 30 | Navigasi gestur, pembatasan peluncuran activity dari background |
| 12 atau 12L | 31, 32 | Pembatasan broadcast penutup dialog, aksi global tutup notifikasi |
| 13 | 33 | Izin notifikasi runtime |
| 14 | 34 | Jenis foreground service wajib |
| 15 | 35 | Edge-to-edge paksa, aturan peluncuran background baru |
| 16 | 36 | Predictive back, perilaku jendela di layar besar |

### Skenario uji

| ID | Skenario | Langkah | Hasil yang diharapkan |
| --- | --- | --- | --- |
| T01 | Prasyarat kurang | Matikan layanan aksesibilitas, buka wizard | Baris aksesibilitas merah, tombol Mulai ujian nonaktif |
| T02 | Mulai normal | Semua prasyarat hijau, Mulai, terima dialog pin | Soal tampil setelah pin aktif, event `EXAM_STARTED` |
| T03 | Pin ditolak | Tekan Batal pada dialog pin | Soal tersembunyi, tombol Aktifkan pin muncul, `GATE_CLOSED` setelah 15 detik |
| T04 | Pin dilepas siswa | Tiga tombol: tahan Back dan Recents. Gestur: geser atas dan tahan | Soal tersembunyi kurang dari 1,5 detik, `GATE_CLOSED` berdetail `pinned`, dialog pin diminta ulang paling banyak 3 kali |
| T05 | Home setelah pin lepas | Setelah T04 tekan Home | Aplikasi ujian muncul kembali, ada `USER_LEAVE_HINT` |
| T06 | Buka aplikasi lain | Setelah pin lepas, buka aplikasi lain dari Recents atau notifikasi | Layar hitam sesaat, aplikasi ujian kembali dalam 2 detik, `FOREIGN_APP` berisi nama paket. Bila tidak kembali: `BRING_FRONT_FAILED` |
| T07 | Tarik notifikasi | Tarik bayangan notifikasi ke bawah | Menutup sendiri dalam kurang dari 1 detik |
| T08 | Layar terbagi atau PiP | Aktifkan layar terbagi setelah pin lepas | Soal tersembunyi, `GATE_CLOSED` berdetail `singleWindow` |
| T09 | Aksesibilitas dimatikan | Matikan layanan di Pengaturan saat ujian | `GUARD_DISABLED`, soal tersembunyi, heartbeat membawa `guard=false` |
| T10 | Offline | Mode pesawat 60 detik, keluar dan masuk aplikasi, lalu online | Event terkirim berurutan setelah online, tanpa duplikat di server |
| T11 | Paksa berhenti | Paksa berhenti aplikasi dari Info Aplikasi | Heartbeat berhenti, server menandai siswa hilang dalam 20 detik |
| T12 | Tangkapan layar | Tombol screenshot dan perekam layar | Hasil hitam atau diblokir sistem |
| T13 | Tombol Back | Tombol dan gestur Back | Tidak ada efek |
| T14 | Layar dimatikan | Tekan tombol daya, nyalakan kembali | Status sesuai kondisi pin; bila pin lepas, pelanggaran tercatat |
| T15 | Selesai ujian | Tekan Selesaikan ujian | Pin lepas, alias Home nonaktif, service berhenti, flag layar dibersihkan, `EXAM_ENDED` terkirim |
| T16 | Activity dihancurkan | Geser aplikasi dari Recents setelah pin lepas | `ACTIVITY_DESTROYED`, aplikasi kembali, jawaban pulih dari server |
| T17 | Device Owner (khusus) | Ulangi T04, T05, dan T07 pada perangkat Device Owner | Tidak ada dialog pin, tombol sistem tidak berfungsi |

### Perintah bantu

```bash
# event yang dicatat aplikasi
adb logcat -s ExamKiosk

# indikasi tarik balik diblokir sistem (teks log berbeda antar versi dan merek)
adb logcat | grep -i "background activity"

# status lock task (nama field dapat berbeda antar versi)
adb shell dumpsys activity activities | grep -i locktask

# layanan aksesibilitas yang aktif, dan izin overlay
adb shell settings get secure enabled_accessibility_services
adb shell appops get com.example.examkiosk SYSTEM_ALERT_WINDOW
```

### Lembar hasil

Salin dan isi satu baris per perangkat. Kolom Gagal diisi ID skenario yang tidak lulus.

| Perangkat | Android | API | Lulus semua | Gagal | Catatan |
| --- | --- | --- | --- | --- | --- |
|  | 8.x | 26 atau 27 |  |  |  |
|  | 9 | 28 |  |  |  |
|  | 10 atau 11 | 29 atau 30 |  |  |  |
|  | 12 | 31 atau 32 |  |  |  |
|  | 13 | 33 |  |  |  |
|  | 14 | 34 |  |  |  |
|  | 15 | 35 |  |  |  |
|  | 16 | 36 |  |  |  |

Kriteria penerimaan: semua baris lulus T01 sampai T16. Perangkat yang berulang kali gagal di T06 (muncul `BRING_FRONT_FAILED`) tidak dibatalkan, tetapi dicatat sebagai perangkat yang hanya aman dengan Device Owner atau dengan pengawasan tambahan.

## Asumsi, risiko, dan rollout

### Asumsi yang belum terverifikasi

Dokumen dan kode ini disusun tanpa dijalankan di perangkat nyata. Enam hal berikut adalah asumsi yang paling menentukan dan harus dibuktikan lewat skenario uji sebelum dipakai ujian sungguhan.

| Asumsi | Bila salah | Dibuktikan oleh |
| --- | --- | --- |
| Layanan aksesibilitas dan foreground service boleh membawa activity ke depan dari background di Android 10 sampai 16 | Tarik balik gagal, hanya overlay yang menutup layar (event `BRING_FRONT_FAILED`) | T06 |
| Aksi global tutup notifikasi bekerja di semua merek Android 12 ke atas | Siswa sempat membaca notifikasi, aplikasi kehilangan fokus | T07 |
| `resizeableActivity=false` dihormati; di Android 16 pada layar besar atribut ini dapat diabaikan | Layar terbagi lolos dari manifest, hanya deteksi `isInMultiWindowMode` yang menangkapnya | T08 |
| `PopScope` bersama predictive back menahan Back di Android 13 sampai 16 | Back keluar dari halaman ujian | T13 |
| Event UsageStats cukup cepat sebagai cadangan saat aksesibilitas mati | Jendela deteksi cadangan lebih lambat dari 500 ms | T06 dengan aksesibilitas dimatikan |
| Dialog pin tidak tertutup oleh `ExamGuardService` | Pin tidak pernah aktif di sebagian versi | T02, T03 |

### Risiko dan batasan

- **Aplikasi asing sempat tampil sekejap.** Tanpa Device Owner tidak ada cara mencegat peluncuran. Lamanya perlu diukur di T06; jangan menjanjikan angka tertentu ke sekolah sebelum diukur.
- **Celah di luar aplikasi.** Perangkat kedua, bantuan orang lain, atau mematikan jaringan tidak bisa dicegah aplikasi. Heartbeat dan kebijakan server (bagian 7) yang menangkapnya.
- **Proses dimatikan sistem.** `ExamForegroundService` memakai `START_NOT_STICKY`, jadi state native hilang bila proses mati. Saat siswa membuka ulang aplikasi, Dart harus memanggil `start` lagi dan memulihkan sesi dari server.
- **Distribusi Play Store.** Layanan aksesibilitas, `PACKAGE_USAGE_STATS`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, dan foreground service `specialUse` semuanya butuh deklarasi atau punya batasan kebijakan di Play. Untuk APK internal, MDM, atau Play privat risikonya jauh lebih kecil. Periksa kebijakan terbaru sebelum memilih saluran distribusi.
- **Privasi dan persetujuan.** Nama paket aplikasi asing dan status perangkat dikirim ke server. Layanan aksesibilitas dikonfigurasi tanpa membaca isi layar, tetapi tetap izin sensitif. Beri tahu siswa dan orang tua apa yang dikumpulkan, kapan aktif, dan berapa lama disimpan.
- **Sisa konfigurasi setelah ujian.** Guard hanya bertindak saat `ExamSession.active`, tetapi layanan aksesibilitas tetap terpasang. Minta siswa mematikannya setelah ujian. Alias Home dinonaktifkan oleh `stopExam`, namun pilihan layar utama bawaan di sebagian perangkat perlu dikembalikan manual.
- **Siswa terjebak.** Bila perlindungan wajib mati di tengah ujian (misalnya OEM mematikan layanan), siswa tidak punya jalan keluar yang sengaja. Siapkan prosedur pengawas: tandai sesi di server, minta siswa menutup paksa aplikasi, lalu ulangi wizard.

### Pemecahan masalah per merek

| Gejala | Penyebab umum | Tindakan |
| --- | --- | --- |
| Layanan aksesibilitas mati sendiri | Penghemat baterai OEM menghentikan layanan latar | Kunci aplikasi di Recents, izinkan mulai otomatis, setel baterai ke tanpa batasan |
| Overlay tidak muncul | Izin tampil di atas aplikasi lain belum diberikan, atau ada izin tambahan merek | Cek Info Aplikasi, izin tambahan atau lainnya (Xiaomi: tampilkan jendela pop-up saat di latar belakang) |
| Tarik balik tidak jalan | Merek membatasi mulai activity dari latar belakang | Aktifkan izin mulai di latar belakang atau jendela pop-up latar belakang pada Info Aplikasi |
| Dialog pin tidak muncul | Fitur sematkan layar dimatikan di Pengaturan pada sebagian versi | Aktifkan menu Sematkan layar (nama menu berbeda tiap merek), masukkan ke SOP persiapan |
| Notifikasi layanan tidak terlihat di Android 13 ke atas | Izin notifikasi ditolak | Wizard baris notifikasi, atau buka pengaturan notifikasi aplikasi |
| Layar hitam overlay menempel | Gerbang pulih tetapi jendela fokus belum kembali | Overlay hilang otomatis setelah 4 detik, periksa `onWindowFocusChanged` |

### Urutan rollout

1. **Percontohan.** Satu perangkat per baris di tabel perangkat minimum, jalankan T01 sampai T17, perbaiki, ulangi sampai lembar hasil hijau.
2. **Allowlist sekolah.** Daftarkan paket yang sah lewat `allowedPackages` (misalnya aplikasi kalkulator atau kamera bila soal membutuhkannya). Tanpa ini, aplikasi itu dianggap pelanggaran.
3. **Uji beban server.** Heartbeat tiap 5 detik berarti jumlah siswa dibagi 5 request per detik di endpoint heartbeat, ditambah event. Uji dengan jumlah siswa terbesar yang Anda rencanakan.
4. **Ujian simulasi dengan pengawas.** Bandingkan catatan pengawas dengan log server untuk menemukan pelanggaran palsu.
5. **Dua sesi pertama dengan kebijakan hanya mencatat.** Jangan langsung auto-submit atau mengunci sesi. Pelanggaran palsu (OEM aneh, dialog sistem yang belum masuk allowlist) akan merugikan siswa yang tidak bersalah.
6. **Aktifkan sanksi** setelah angka pelanggaran palsu dari dua sesi itu rendah dan Anda tahu perangkat mana yang butuh Device Owner.

### Langkah berikutnya

Kirimkan `LockdownPlugin.kt`, `MainActivity.kt`, dan `AntiCheatPlugin.kt` Anda yang sekarang, beserta hasil lembar uji dan log `adb logcat -s ExamKiosk`. Dengan itu penggabungan ke kode lama, pembersihan fitur duplikat, dan perbaikan temuan uji bisa dikerjakan secara konkret.
