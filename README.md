# Lockdown CBT - Computer Based Test Lockdown Application

Aplikasi Flutter untuk lockdown mode saat ujian online (CBT) dengan monitoring keamanan real-time.

## 🎯 Fitur Utama

### Lockdown Engine
- ✅ Fullscreen Mode
- ✅ Block App Switching (Alt+Tab, Win+Tab)
- ✅ Block System Shortcuts (Win+D, Win+L, Ctrl+Alt+Del, Alt+F4)
- ✅ Disable Window Controls (Close, Minimize, Maximize)
- ✅ Block Context Menu (Right-click)
- ✅ Disable Copy/Paste
- ✅ Kiosk Mode (Disable Task Manager)

### Anti-Cheat Engine
- ✅ Focus Monitor (Detect app switching)
- ✅ Process Monitor (Detect blacklisted apps)
- ✅ Display Monitor (Detect multiple monitors, remote desktop)
- ✅ Screenshot Monitor (Capture on suspicious activity)
- ✅ Clipboard Monitor
- ✅ Security Event Logger (Real-time upload ke server)

### WebView Engine
- ✅ Flexible URL support (Google Form, Quizizz, custom exam)
- ✅ Navigation Control
- ✅ JavaScript Bridge (Flutter ↔ WebView communication)
- ✅ Download Control (Block downloads)
- ✅ Popup Control (Block popups)
- ✅ DevTools Control (Disable inspect)
- ✅ Cache Control

## 🏗️ Arsitektur

```
lockdown_engine/
├── lib/                           # Flutter (Dart) Layer
│   ├── app/                       # App configuration
│   │   ├── routes/                # GetX routing
│   │   └── themes/                # Material 3 theme
│   │
│   ├── core/                      # Core utilities
│   │   ├── config/                # App config (flexible base URL)
│   │   ├── constants/             # Event types, API endpoints
│   │   └── utils/                 # Device info, image compression
│   │
│   ├── data/                      # Data layer
│   │   ├── models/                # Data models
│   │   ├── providers/             # API provider (Dio)
│   │   └── repositories/          # Repositories
│   │
│   ├── modules/                   # Feature modules
│   │   ├── splash/                # Splash screen
│   │   ├── setup/                 # Setup URL screen
│   │   └── exam/                  # Exam screen dengan WebView
│   │
│   └── services/                  # Services
│       ├── lockdown/              # Lockdown service
│       ├── anticheat/             # AntiCheat monitoring services
│       └── webview/               # WebView service & JS bridge
│
├── windows/runner/                # Windows Native (C++)
│   ├── lockdown_plugin.h/cpp      # Windows lockdown implementation
│   └── anticheat_plugin.h/cpp     # Windows process monitoring
│
└── android/.../                   # Android Native (Kotlin)
    ├── MainActivity.kt            # Main activity dengan plugin registration
    ├── LockdownPlugin.kt          # Android lockdown implementation
    └── AntiCheatPlugin.kt         # Android process monitoring
```

## 📦 Dependencies

```yaml
# State Management
get: ^4.6.6

# WebView
flutter_inappwebview: ^6.0.0

# Network & API
dio: ^5.4.0

# Storage
get_storage: ^2.1.1

# Device Info
device_info_plus: ^10.1.0

# Window Management (Windows)
window_manager: ^0.3.9
screen_retriever: ^0.1.9

# Screenshot
screenshot: ^3.0.0
image: ^4.1.7

# Utils
intl: ^0.19.0
uuid: ^4.4.0
permission_handler: ^11.3.1
```

## 🚀 Cara Penggunaan

### Prerequisites
- Flutter SDK 3.13.2+
- Dart 3.13.2+
- Windows 10+ (untuk Windows build)
- Android SDK 26+ (untuk Android build)

### Installation

1. Clone repository
```bash
git clone <repository-url>
cd lockdown_engine
```

2. Install dependencies
```bash
flutter pub get
```

3. Run aplikasi
```bash
# Windows
flutter run -d windows

# Android
flutter run -d <device-id>
```

### Build Release

```bash
# Windows
flutter build windows --release

# Android
flutter build apk --release
```

## 🔧 Konfigurasi

### Base URL API (Flexible)
Edit di `lib/core/config/app_config.dart`:
```dart
static String baseUrl = 'https://your-api.com/api';
```

Atau set secara dinamis saat runtime.

### Package Name
Package sudah diset ke: `com.louissoe.lockdown_cbt`

## 📡 API Integration (Laravel Backend)

### Expected Endpoints

**Start Exam**
```
POST /api/exam/start
Body: {
  "exam_url": "https://forms.google.com/...",
  "device_id": "uuid",
  "device_info": {...}
}
Response: {
  "session_id": "session_123",
  "exam_url": "https://forms.google.com/...",
  "duration": 90,
  "start_time": "2026-09-04T10:00:00Z"
}
```

**Upload Security Events**
```
POST /api/monitoring/events
Body: {
  "session_id": "session_123",
  "events": [
    {
      "id": "event_1",
      "type": "FOCUS_LOST",
      "timestamp": "2026-09-04T10:05:00Z",
      "data": {...}
    }
  ]
}
```

**Upload Screenshot**
```
POST /api/monitoring/screenshot
Body: {
  "session_id": "session_123",
  "event_id": "event_1",
  "screenshot": "base64_encoded_image"
}
```

**Validate Exit Password**
```
POST /api/exam/validate-password
Body: {
  "session_id": "session_123",
  "password": "admin123"
}
Response: {
  "is_valid": true
}
```

**Finish Exam**
```
POST /api/exam/finish
Body: {
  "session_id": "session_123",
  "reason": "completed|timeout|forced_exit"
}
```

## 🎮 User Flow

1. **Splash Screen** → Initialize app
2. **Setup URL Screen** → Enter exam URL (Google Form/Quizizz/Custom)
3. **Exam Screen** → Auto-enable lockdown
4. **Exit** → Password validation dari server

## ⚙️ Lockdown Features (Platform Specific)

### Windows
- ✅ Keyboard hooks untuk block shortcuts
- ✅ Window style manipulation untuk fullscreen
- ✅ Registry edit untuk disable Task Manager
- ✅ Process enumeration untuk detect blacklisted apps
- ✅ Multi-monitor detection
- ✅ Remote desktop detection

### Android
- ✅ Lock Task Mode (Kiosk Mode)
- ✅ FLAG_SECURE (Prevent screenshots)
- ✅ System UI flags untuk hide navigation
- ✅ Back button blocking
- ✅ Process monitoring (limited di Android 5.0+)

## 🔐 Security Event Types

```
FOCUS_LOST          - App kehilangan focus
APP_SWITCH_ATTEMPT  - User mencoba switch app
SHORTCUT_BLOCKED    - Shortcut key blocked
PROCESS_VIOLATION   - Blacklisted process detected
DISPLAY_CHANGED     - Multiple monitor atau RDP detected
CLIPBOARD_ACTIVITY  - Copy/paste activity
SCREENSHOT_TAKEN    - Screenshot captured
NAVIGATION_ATTEMPT  - WebView navigation attempt
DOWNLOAD_BLOCKED    - Download attempt blocked
POPUP_BLOCKED       - Popup blocked
EXAM_STARTED        - Exam session started
EXAM_FINISHED       - Exam session finished
```

## ⚠️ Known Limitations

### Windows
- Requires admin privileges untuk beberapa fitur (Task Manager disable)
- Antivirus mungkin flag keyboard hooks sebagai suspicious
- User dengan admin rights bisa bypass beberapa proteksi

### Android
- Device Admin permission harus di-grant manual oleh user
- Lock Task Mode butuh user confirmation (atau device owner)
- Process monitoring terbatas di Android 5.0+
- Split screen dan multi-window sulit di-block 100%

### General
- Network blocking di-skip (requirement change)
- Camera monitoring belum diimplementasi (future)
- Tidak bisa prevent user pakai device kedua untuk cheat

## 🧪 Testing

### Test Exit Password (Development Mode)
Default password untuk testing (jika backend belum ready):
- `admin`
- `123456`

### Test dengan Google Form
1. Buat Google Form untuk testing
2. Copy URL form
3. Paste di Setup URL screen
4. Start exam

## 📱 Minimum Requirements

- **Windows**: Windows 10 version 1809 or later
- **Android**: Android 8.0 (API level 26) or later

## 🛠️ Development

### Folder Structure
- `lib/` - Flutter/Dart code
- `windows/runner/` - Windows native C++ code
- `android/app/src/main/kotlin/` - Android native Kotlin code

### Adding New Features
1. Create service di `lib/services/`
2. Implement native code di `windows/runner/` dan `android/.../`
3. Register di `ExamBinding` (`lib/app/routes/app_pages.dart`)
4. Update `ExamController` untuk use service

## 📄 License

Proprietary - All rights reserved

## 👨‍💻 Developer

Louis Soe - Universitas Multimedia Nusantara
Semester 4 Project - 2026

---

**Note:** Aplikasi ini dibuat untuk tujuan educational dan security testing. Pastikan comply dengan privacy laws dan inform users tentang monitoring yang dilakukan.
