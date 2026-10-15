# Screen Share — Dokumentasi Backend

Dokumen ini menjelaskan arsitektur, protokol WebSocket, dan struktur backend Laravel yang dibutuhkan untuk mendukung fitur screen share real-time pada aplikasi Lockdown CBT.

---

## 1. Gambaran Arsitektur

```
Device Peserta (Flutter)
        │
        │  WebSocket (ws://domain/app/{app-key})
        │  Kirim frame JPEG base64 setiap 1 detik
        ▼
Laravel Reverb (WebSocket Server)
        │
        │  Broadcast event ke channel per sesi ujian
        │  Channel: exam-screen.{session_id}
        ▼
Dashboard Pengawas (Browser)
        │
        │  Subscribe ke channel peserta via Laravel Echo
        │  Tampilkan frame sebagai gambar yang terus diperbarui
        ▼
Redis (opsional, untuk scale horizontal)
        │
        │  Pub/Sub antar worker jika Reverb dijalankan multi-instance
```

### Komponen

| Komponen | Teknologi | Fungsi |
|---|---|---|
| WebSocket Server | Laravel Reverb | Menerima koneksi dari Flutter, broadcast frame ke pengawas |
| Event | Laravel Broadcasting | Membungkus data frame dan mendistribusikannya ke channel |
| Channel Auth | Laravel Channel Routes | Memastikan hanya peserta dengan session valid yang bisa connect |
| Redis | Redis (opsional) | Pub/Sub untuk deployment multi-server |

---

## 2. Protokol WebSocket

Semua pesan dikirim dalam format JSON. Flutter mengirim ke server, server bisa kirim balik ack atau instruksi.

### 2.1 Event dari Flutter ke Server

#### `screen.join` — Peserta masuk exam
Dikirim sekali saat WebSocket berhasil terhubung.

```json
{
  "event": "screen.join",
  "data": {
    "session_id": "abc123",
    "device_id": "865213041234567"
  }
}
```

#### `screen.frame` — Frame layar (dikirim setiap 1 detik)
Dikirim secara periodik selama exam berlangsung.
Frame yang identik dengan frame sebelumnya akan di-skip oleh Flutter (tidak dikirim).

```json
{
  "event": "screen.frame",
  "data": {
    "session_id": "abc123",
    "frame": "<base64 encoded JPEG string>",
    "timestamp": 1725868800000,
    "size": 18432
  }
}
```

| Field | Tipe | Keterangan |
|---|---|---|
| `session_id` | string | ID sesi ujian |
| `frame` | string | JPEG 960x540 quality 50%, di-encode ke base64 |
| `timestamp` | int | Unix timestamp dalam milidetik |
| `size` | int | Ukuran JPEG dalam bytes sebelum base64 |

#### `screen.leave` — Peserta selesai exam
Dikirim sekali saat exam selesai atau force close.

```json
{
  "event": "screen.leave",
  "data": {
    "session_id": "abc123"
  }
}
```

---

### 2.2 Event dari Server ke Flutter (opsional)

Server dapat mengirim event balik untuk keperluan kontrol. Saat ini Flutter hanya menerima dan log pesan ini.

#### `server.ping` — Keepalive dari server
```json
{
  "event": "server.ping",
  "data": {}
}
```

#### `server.ack` — Konfirmasi join berhasil
```json
{
  "event": "server.ack",
  "data": {
    "session_id": "abc123",
    "status": "connected"
  }
}
```

---

## 3. Struktur Backend Laravel

Berikut daftar file yang perlu dibuat atau diubah di project Laravel.

### 3.1 Konfigurasi

#### `config/broadcasting.php`
Pastikan driver default diset ke `reverb`. Tidak perlu perubahan besar jika menggunakan konfigurasi default Laravel 11.

#### `.env` (Laravel)
```env
BROADCAST_CONNECTION=reverb

REVERB_APP_ID=lockdown-cbt
REVERB_APP_KEY=your-reverb-app-key
REVERB_APP_SECRET=your-reverb-app-secret
REVERB_HOST=0.0.0.0
REVERB_PORT=8080
REVERB_SCHEME=http

REVERB_MAX_REQUEST_SIZE=5000000  # 5MB — untuk menampung frame base64

REDIS_HOST=127.0.0.1
REDIS_PORT=6379
```

> **Catatan:** `REVERB_MAX_REQUEST_SIZE` perlu dinaikkan karena setiap frame bisa mencapai ~25KB setelah base64 encoding.

---

### 3.2 Routes

#### `routes/api.php`
Endpoint HTTP untuk validasi dan logging sesi screen share.

| Method | Endpoint | Fungsi |
|---|---|---|
| `POST` | `/screen-share/join` | Validasi session sebelum WebSocket connect |
| `POST` | `/screen-share/leave` | Log waktu peserta disconnect |
| `GET` | `/screen-share/status/{session_id}` | Cek status stream peserta (aktif/tidak) |

#### `routes/channels.php`
Otentikasi channel private. Hanya peserta dengan `session_id` valid yang bisa subscribe.

```
Channel: exam-screen.{session_id}
Tipe: Private Channel
Auth: Cek apakah session_id milik user yang sedang login / token valid
```

---

### 3.3 Events

#### `Events/ScreenFrameReceived.php`
Event Laravel Broadcasting yang di-trigger setiap kali server menerima frame dari Flutter.

- **Implements:** `ShouldBroadcast`
- **Channel:** `exam-screen.{session_id}` (private)
- **Data yang di-broadcast ke pengawas:**
  - `session_id`
  - `frame` (base64 JPEG)
  - `timestamp`
  - `device_id`

#### `Events/ScreenShareJoined.php`
Di-trigger saat peserta berhasil join. Berguna untuk notifikasi ke dashboard pengawas bahwa peserta mulai stream.

#### `Events/ScreenShareLeft.php`
Di-trigger saat peserta disconnect. Dashboard pengawas akan tahu stream berhenti.

---

### 3.4 Controllers

#### `Http/Controllers/ScreenShareController.php`
Menangani request HTTP dari Flutter.

**Method `join()`**
- Terima `session_id` + `device_id`
- Validasi session aktif di database
- Catat waktu mulai stream
- Return 200 jika valid, 422 jika tidak

**Method `leave()`**
- Terima `session_id`
- Catat waktu stream berakhir
- Return 200

**Method `handleFrame()`**
- Menerima frame dari Flutter via WebSocket (bukan HTTP)
- Di-handle langsung oleh Reverb, bukan controller HTTP
- Controller ini hanya untuk endpoint metadata

---

### 3.5 WebSocket Handler (Reverb)

Reverb menangani koneksi WebSocket secara langsung. Untuk memproses event kustom (`screen.frame`, `screen.join`, `screen.leave`) yang dikirim Flutter, perlu dibuat **Reverb Channel Handler** atau gunakan **Laravel Echo Server** dengan custom listener.

Cara yang direkomendasikan di Laravel Reverb:

```
App\Http\Controllers\ScreenShareController
    └─► Listen event masuk dari Flutter via Reverb webhook/queue
    └─► Dispatch ScreenFrameReceived event
    └─► Reverb broadcast ke channel exam-screen.{session_id}
    └─► Dashboard pengawas (Laravel Echo) terima frame
```

Alternatif lebih simpel untuk development awal:
- Flutter kirim frame via **HTTP POST** ke endpoint API biasa
- Server simpan frame terbaru per session di Redis
- Dashboard pengawas polling Redis setiap 1 detik via SSE (Server-Sent Events)

> Pendekatan ini lebih mudah diimplementasikan dan tidak butuh WebSocket handler kustom di Reverb.

---

## 4. Setup Laravel Reverb

### Langkah Instalasi

```bash
# 1. Install Reverb via Composer
composer require laravel/reverb

# 2. Publish konfigurasi Reverb
php artisan reverb:install

# 3. Install Laravel Echo dan Pusher JS di frontend (dashboard pengawas)
npm install --save-dev laravel-echo pusher-js

# 4. Jalankan Reverb server
php artisan reverb:start --host=0.0.0.0 --port=8080

# 5. Jalankan queue worker (untuk broadcast)
php artisan queue:work
```

### Untuk Production

```bash
# Gunakan Supervisor untuk menjaga Reverb tetap berjalan
# Contoh konfigurasi /etc/supervisor/conf.d/reverb.conf:
#
# [program:reverb]
# command=php /var/www/html/artisan reverb:start --host=0.0.0.0 --port=8080
# autostart=true
# autorestart=true
# user=www-data
```

---

## 5. Konfigurasi Flutter (.env)

Sesuaikan `WS_URL` di file `.env` Flutter dengan format URL Reverb:

```env
# Format: ws://{host}:{port}/app/{REVERB_APP_KEY}
WS_URL=ws://your-domain.com:8080/app/your-reverb-app-key

# Jika menggunakan HTTPS/WSS di production:
WS_URL=wss://your-domain.com/app/your-reverb-app-key
```

> **Catatan:** Saat development dengan HTTP, gunakan `ws://`. Saat production dengan SSL, ganti ke `wss://` dan update `BASE_URL` ke `https://`.

---

## 6. Flow Lengkap Per Skenario

### Skenario 1 — Peserta mulai ujian

```
1. Flutter POST /exam/start → dapat session_id
2. Flutter connect WebSocket ws://domain:8080/app/{key}?session_id=abc&device_id=xyz
3. Reverb terima koneksi → validasi session via channel auth
4. Flutter kirim event "screen.join"
5. Server log waktu mulai stream
6. Flutter mulai kirim "screen.frame" setiap 1 detik
7. Reverb broadcast frame ke channel exam-screen.abc
8. Dashboard pengawas (jika sudah ada) tampilkan frame real-time
```

### Skenario 2 — Peserta selesai ujian

```
1. Flutter kirim event "screen.leave"
2. Flutter disconnect WebSocket
3. Server log waktu stream berakhir
4. Dashboard pengawas notifikasi "Peserta selesai"
```

### Skenario 3 — Koneksi terputus (network drop)

```
1. WebSocket terputus tiba-tiba
2. Flutter detect onDone/onError
3. Flutter jadwalkan reconnect dengan backoff: 2s, 4s, 6s, 8s, 10s
4. Setelah reconnect berhasil, Flutter kirim "screen.join" lagi
5. Stream dilanjutkan otomatis
6. Maksimal 5 kali percobaan reconnect
```

### Skenario 4 — Force close / crash

```
1. App ditutup paksa
2. WebSocket timeout di server (tidak ada heartbeat)
3. Server anggap peserta disconnect setelah timeout
4. Dashboard pengawas notifikasi "Koneksi terputus"
```

---

## 7. Estimasi Beban Server

Dengan 100 peserta ujian serentak per kelas:

| Metrik | Nilai |
|---|---|
| Ukuran frame JPEG per kirim | ~15–25 KB |
| Interval | 1 detik (1fps) |
| Bandwidth per peserta | ~20 KB/s |
| Bandwidth total (100 peserta) | ~2 MB/s |
| Koneksi WebSocket aktif | 100 per kelas |
| RAM Reverb estimasi | ~50–100 MB untuk 100 koneksi |

> Frame identik di-skip oleh Flutter (tidak dikirim), sehingga saat peserta diam membaca soal, bandwidth mendekati 0.

---

## 8. Catatan Platform

### Android
- `FLAG_SECURE` aktif saat lockdown — mencegah screenshot system oleh user.
- `RepaintBoundary.toImage()` yang dipakai Flutter untuk capture **tidak terpengaruh** oleh `FLAG_SECURE` karena capture dilakukan dari dalam widget tree Flutter, bukan via sistem operasi.
- Screen share tetap berjalan normal.

### Windows
- Tidak ada batasan dari sistem operasi.
- `RepaintBoundary.toImage()` bekerja langsung.
- Frame di-encode di Dart Isolate terpisah — tidak mempengaruhi performa UI exam.

### iOS (jika didukung di masa depan)
- Perlu review izin screen capture.
- `RepaintBoundary.toImage()` seharusnya bekerja untuk konten Flutter native.
- Konten WebView (`WKWebView`) mungkin perlu pendekatan berbeda.
