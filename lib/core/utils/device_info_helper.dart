import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:get_storage/get_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceInfoHelper {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static final GetStorage _storage = GetStorage();
  static const String _deviceIdKey = 'device_id';

  /// Mengembalikan hardware ID perangkat.
  /// - Android: androidInfo.id (Android ID)
  /// - Windows: windowsInfo.deviceId (machine GUID)
  /// - Fallback: UUID persisten di GetStorage
  static Future<String> getDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final id = androidInfo.id; // Android ID (hardware-backed)
        if (id.isNotEmpty) return id;
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        final id = windowsInfo.deviceId; // Machine GUID dari registry
        if (id.isNotEmpty) return id;
      }
    } catch (e) {
      print('[DeviceInfoHelper] Gagal ambil hardware ID: $e');
    }

    // Fallback: UUID persisten
    String? deviceId = _storage.read(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await _storage.write(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      return {
        'platform': 'android',
        'model': androidInfo.model,
        'manufacturer': androidInfo.manufacturer,
        'version': androidInfo.version.release,
        'sdk': androidInfo.version.sdkInt,
        'device_id': await getDeviceId(),
      };
    } else if (Platform.isWindows) {
      final windowsInfo = await _deviceInfo.windowsInfo;
      return {
        'platform': 'windows',
        'computer_name': windowsInfo.computerName,
        'version': windowsInfo.displayVersion,
        'build': windowsInfo.buildNumber,
        'device_id': await getDeviceId(),
      };
    }

    return {
      'platform': Platform.operatingSystem,
      'device_id': await getDeviceId(),
    };
  }
}
