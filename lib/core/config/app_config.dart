import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_storage/get_storage.dart';

class AppConfig {
  static const String _customBaseUrlKey = 'custom_base_url';
  static const String _adminPinKey = 'custom_admin_pin';
  static const String defaultAdminPin = 'admincbt';

  /// Mengambil Base URL kustom jika telah diatur oleh administrator
  static String? get customBaseUrl {
    try {
      final box = GetStorage();
      final url = box.read<String>(_customBaseUrlKey)?.trim();
      if (url != null && url.isNotEmpty) {
        return url;
      }
    } catch (_) {}
    return null;
  }

  /// Mengecek apakah aplikasi sedang menggunakan Base URL kustom
  static bool get isUsingCustomBaseUrl => customBaseUrl != null;

  /// Base URL default sistem yang dibaca dari file .env
  static String get defaultBaseUrl =>
      dotenv.env['BASE_URL'] ?? 'http://your-api-domain.com/api';

  /// Base URL aktif: jika ada nilai kustom dari admin maka pakai nilai tersebut;
  /// jika tidak ada, gunakan default dari .env
  static String get baseUrl {
    final custom = customBaseUrl;
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return defaultBaseUrl;
  }

  /// Menyimpan Base URL kustom baru (otomatis normalisasi trailing slash)
  static Future<void> setCustomBaseUrl(String? url) async {
    try {
      final box = GetStorage();
      final clean = url?.trim() ?? '';
      if (clean.isEmpty) {
        await box.remove(_customBaseUrlKey);
      } else {
        final normalized = clean.endsWith('/')
            ? clean.substring(0, clean.length - 1)
            : clean;
        await box.write(_customBaseUrlKey, normalized);
      }
    } catch (_) {}
  }

  /// Menghapus Base URL kustom dan kembali ke default .env
  static Future<void> resetBaseUrlToDefault() async {
    try {
      final box = GetStorage();
      await box.remove(_customBaseUrlKey);
    } catch (_) {}
  }

  /// Memverifikasi PIN Administrator (default: admincbt atau cbtadmin)
  static bool verifyAdminPin(String inputPin) {
    final clean = inputPin.trim().toLowerCase();
    if (clean.isEmpty) return false;

    try {
      final box = GetStorage();
      final customPin = box.read<String>(_adminPinKey)?.trim().toLowerCase();
      if (customPin != null && customPin.isNotEmpty) {
        return clean == customPin || clean == defaultAdminPin;
      }
    } catch (_) {}

    return clean == defaultAdminPin || clean == 'cbtadmin';
  }

  /// Mengubah PIN Administrator jika diperlukan
  static Future<void> setAdminPin(String newPin) async {
    try {
      final box = GetStorage();
      final clean = newPin.trim().toLowerCase();
      if (clean.isEmpty || clean == defaultAdminPin) {
        await box.remove(_adminPinKey);
      } else {
        await box.write(_adminPinKey, clean);
      }
    } catch (_) {}
  }

  // App Configuration
  static const String appName = 'Lockdown CBT';
  static const String appVersion = '1.0.0';

  // Monitoring Configuration
  static const int eventBatchSize = 10;
  static const Duration eventUploadInterval = Duration(seconds: 5);

  // Screenshot Configuration
  static const int screenshotQuality = 80;
  static const int screenshotMaxWidth = 1920;
  static const int screenshotMaxHeight = 1080;

  // Process Monitoring
  static const Duration processMonitorInterval = Duration(seconds: 5);

  // Timer Configuration
  static const Duration timerUpdateInterval = Duration(seconds: 1);
}
