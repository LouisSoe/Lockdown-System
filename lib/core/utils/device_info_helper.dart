import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:get_storage/get_storage.dart';

class DeviceInfoHelper {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static final GetStorage _storage = GetStorage();
  static const String _deviceIdKey = 'device_id';
  
  static Future<String> getDeviceId() async {
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
