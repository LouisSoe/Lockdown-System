# Panduan Migrasi: Opsi B (Anti-Block Google Play Protect & Bebas Restricted Settings)

Dokumen ini berisi panduan langkah-demi-langkah untuk mengubah sistem **Lockdown CBT Engine** ke **Opsi B (Lightweight Kiosk)** kapan pun Anda butuhkan.

---

## 🎯 Tujuan Opsi B
1. **Lolos 100% dari blokir Google Play Protect** saat APK diinstal di HP siswa.
2. **Bebas dari pesan error Android 13–15**: *"App was denied access, access to this permission can put your personal and financial info at risk"* (*Restricted Settings*).
3. Siswa tidak perlu repot mencari menu Aksesibilitas di pengaturan HP sebelum ujian.
4. **Fitur Pin Layar (Screen Pinning), Deteksi Keluar (Unpin), Layar Jeda Ujian, Counter Pelanggaran, dan Tombol Pin Ulang tetap berjalan 100% normal.**

---

## 🛠️ Langkah Perubahan Kode

Hanya ada **3 berkas** yang perlu diubah.

---

### 1. `android/app/src/main/AndroidManifest.xml`

Buka file [AndroidManifest.xml](file:///c:/Kuliah/smt4/lockdown_engine/android/app/src/main/AndroidManifest.xml).

#### A. Hapus Izin-Izin Sensitif & Redundan
Hapus baris-baris berikut dari daftar `<uses-permission>`:

```xml
<!-- HAPUS 4 BARIS BERIKUT: -->
<uses-permission android:name="android.permission.DISABLE_KEYGUARD" />
<uses-permission android:name="android.permission.EXPAND_STATUS_BAR" />
<uses-permission android:name="android.permission.ACCESS_NOTIFICATION_POLICY" />
<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS"
    tools:ignore="ProtectedPermissions" />
```

#### B. Hapus Service Aksesibilitas (`ExamGuardService`)
Cari dan hapus blok `<service>` untuk `ExamGuardService`:

```xml
<!-- HAPUS BLOK SERVICE INI: -->
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
```

*(Catatan: File `ExamGuardService.kt` tidak wajib dihapus, cukup hapus deklarasinya dari AndroidManifest agar sistem Android dan Play Protect tidak lagi mengenalinya).*

---

### 2. `android/app/src/main/kotlin/com/louissoe/lockdown_cbt/KioskStatus.kt`

Buka file [KioskStatus.kt](file:///c:/Kuliah/smt4/lockdown_engine/android/app/src/main/kotlin/com/louissoe/lockdown_cbt/KioskStatus.kt).

#### A. Hapus Cek `guard`
Cari baris 37:
```kotlin
// SEBELUM:
val guard = ExamGuardService.connected
val overlay = Settings.canDrawOverlays(ctx)

// UBAH MENJADI:
val guard = true // Selalu true karena aksesibilitas tidak lagi diwajibkan
val overlay = Settings.canDrawOverlays(ctx)
```

#### B. Sesuaikan `missing` dan `prereqOk`
Cari baris 48–52:
```kotlin
// SEBELUM:
val missing = buildList {
    if (!guard) add("guard")
    if (!overlay) add("overlay")
    if (!battery) add("battery")
    if (!notif) add("notif")
    ...
}

// UBAH MENJADI:
val missing = buildList {
    // Cek guard dihapus
    if (!overlay) add("overlay")
    if (!battery) add("battery")
    if (!notif) add("notif")
    ...
}
```

Dan pada baris 69:
```kotlin
// SEBELUM:
"prereqOk" to (guard && overlay && battery && notif),

// UBAH MENJADI:
"prereqOk" to (overlay && battery && notif),
```

---

### 3. `lib/kiosk/preflight_page.dart`

Buka file [preflight_page.dart](file:///c:/Kuliah/smt4/lockdown_engine/lib/kiosk/preflight_page.dart).

Cari daftar `_items` di baris 19:

```dart
// SEBELUM:
static const _items = <_Item>[
  _Item('guard', 'Layanan aksesibilitas "Penjaga Ujian" aktif', true, KioskSetting.guard),
  _Item('overlay', 'Izin tampil di atas aplikasi lain', true, KioskSetting.overlay),
  _Item('battery', 'Optimasi baterai dimatikan untuk aplikasi ini', true, KioskSetting.battery),
  _Item('notif', 'Izin notifikasi', true, KioskSetting.notif),
  _Item('usage', 'Akses penggunaan aplikasi (cadangan deteksi)', false, KioskSetting.usage),
  _Item('home', 'Aplikasi ujian sebagai layar utama', false, KioskSetting.home),
];

// UBAH MENJADI:
static const _items = <_Item>[
  _Item('overlay', 'Izin tampil di atas aplikasi lain', true, KioskSetting.overlay),
  _Item('battery', 'Optimasi baterai dimatikan untuk aplikasi ini', true, KioskSetting.battery),
  _Item('notif', 'Izin notifikasi', true, KioskSetting.notif),
  _Item('home', 'Aplikasi ujian sebagai layar utama', false, KioskSetting.home),
];
```

---

## 🧪 Cara Pengujian Setelah Perubahan

1. Bersihkan build lama dan buat APK baru:
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --debug
   # atau untuk release:
   flutter build apk --release
   ```

2. Pasang APK di HP Android:
   - Kirim file `.apk` ke HP via WhatsApp, Google Drive, atau kabel.
   - Buka file dan tekan **Instal**.
   - **Hasil:** Aplikasi terinstal langsung **tanpa dialog blokir Play Protect**.

3. Masuk ke Aplikasi dan Jalankan Ujian:
   - Di halaman persiapan (*Preflight*), izin yang diminta tinggal **Overlay, Baterai, dan Notifikasi**.
   - Tekan **Mulai Ujian**.
   - Tekan **Sematkan Layar (Pin)** saat dialog sistem Android muncul.
   - Coba lepas pin layar (tekan tahan Back + Recent):
     👉 Layar **"Ujian Dijeda: Penyematan layar (pin) tidak aktif"** langsung muncul beserta tombol **"Aktifkan Pin Layar"** dan hitungan pelanggaran otomatis bertambah.

---

## 🔄 Cara Kembali ke Mode Penuh (Rollback)
Jika suatu saat Anda ingin kembali mengaktifkan `ExamGuardService` (misalnya untuk penggunaan di lab sekolah berbasis Device Owner/MDM):
- Kembalikan deklarasi service di `AndroidManifest.xml`.
- Kembalikan item `guard` di `KioskStatus.kt` dan `preflight_page.dart`.
