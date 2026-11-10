import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/core/constants/event_types.dart';
import 'package:lockdown_engine/services/anticheat/security_logger_service.dart';

class DisplayMonitorService extends GetxService {
  static const MethodChannel _channel = MethodChannel('anticheat_channel');
  
  SecurityLoggerService? _securityLogger;
  Timer? _monitorTimer;
  bool _isMonitoring = false;
  
  int _lastDisplayCount = 1;
  bool _wasRemoteDesktop = false;
  
  void startMonitoring() async {
    if (!Platform.isWindows) {
      print('ℹ Display monitoring skipped on non-Windows platform');
      return;
    }
    if (_isMonitoring) return;
    
    _securityLogger = Get.find<SecurityLoggerService>();
    _isMonitoring = true;
    
    // Get initial state
    _lastDisplayCount = await _getDisplayCount();
    _wasRemoteDesktop = await _isRemoteDesktop();
    
    _monitorTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkDisplayChanges(),
    );
    
    print('✓ Display monitoring started');
  }
  
  void stopMonitoring() {
    if (!_isMonitoring) return;
    
    _monitorTimer?.cancel();
    _isMonitoring = false;
    _securityLogger = null;
    
    print('✓ Display monitoring stopped');
  }
  
  Future<void> _checkDisplayChanges() async {
    try {
      final currentDisplayCount = await _getDisplayCount();
      final isRemoteNow = await _isRemoteDesktop();
      
      // Check display count change
      if (currentDisplayCount != _lastDisplayCount) {
        _securityLogger?.logEvent(
          type: EventTypes.DISPLAY_CHANGED,
          data: {
            'previous_count': _lastDisplayCount,
            'current_count': currentDisplayCount,
            'timestamp': DateTime.now().toIso8601String(),
          },
          captureScreenshot: true,
        );
        
        print('⚠ Display count changed: $_lastDisplayCount -> $currentDisplayCount');
        _lastDisplayCount = currentDisplayCount;
      }
      
      // Check remote desktop activation
      if (isRemoteNow && !_wasRemoteDesktop) {
        _securityLogger?.logEvent(
          type: EventTypes.DISPLAY_CHANGED,
          data: {
            'remote_desktop': true,
            'timestamp': DateTime.now().toIso8601String(),
          },
          captureScreenshot: true,
        );
        
        print('⚠ Remote desktop detected');
      }
      
      _wasRemoteDesktop = isRemoteNow;
    } catch (e) {
      print('✗ Display monitor error: $e');
    }
  }
  
  Future<int> _getDisplayCount() async {
    try {
      final result = await _channel.invokeMethod('getDisplayCount');
      return result ?? 1;
    } catch (e) {
      print('✗ Get display count error: $e');
      return 1;
    }
  }
  
  Future<bool> _isRemoteDesktop() async {
    try {
      final result = await _channel.invokeMethod('isRemoteDesktop');
      return result ?? false;
    } catch (e) {
      print('✗ Check remote desktop error: $e');
      return false;
    }
  }
  
  @override
  void onClose() {
    stopMonitoring();
    super.onClose();
  }
}
