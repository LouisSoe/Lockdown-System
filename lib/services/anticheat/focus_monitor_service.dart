import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/core/constants/event_types.dart';
import 'package:lockdown_engine/services/anticheat/security_logger_service.dart';

class FocusMonitorService extends GetxService with WidgetsBindingObserver {
  SecurityLoggerService? _securityLogger;
  int focusLossCount = 0;
  bool _isMonitoring = false;
  
  void startMonitoring() {
    if (_isMonitoring) return;
    
    _securityLogger = Get.find<SecurityLoggerService>();
    WidgetsBinding.instance.addObserver(this);
    _isMonitoring = true;
    
    print('✓ Focus monitoring started');
  }
  
  void stopMonitoring() {
    if (!_isMonitoring) return;
    
    WidgetsBinding.instance.removeObserver(this);
    _isMonitoring = false;
    _securityLogger = null;
    
    print('✓ Focus monitoring stopped');
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isMonitoring || _securityLogger == null) return;
    
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      focusLossCount++;
      
      _securityLogger!.logEvent(
        type: EventTypes.FOCUS_LOST,
        data: {
          'count': focusLossCount,
          'state': state.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        },
        captureScreenshot: true,
      );
      
      print('⚠ Focus lost (Count: $focusLossCount)');
    } else if (state == AppLifecycleState.resumed) {
      _securityLogger!.logEvent(
        type: EventTypes.FOCUS_GAINED,
        data: {
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      print('✓ Focus regained');
    }
  }
  
  int getFocusLossCount() => focusLossCount;
  
  @override
  void onClose() {
    stopMonitoring();
    super.onClose();
  }
}
