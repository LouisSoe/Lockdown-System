import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // API Configuration — dibaca dari .env
  static String get baseUrl =>
      dotenv.env['BASE_URL'] ?? 'http://your-api-domain.com/api';

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
