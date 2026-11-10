import 'dart:io' show Platform;
import 'package:get/get.dart';
import 'package:lockdown_engine/services/anticheat/security_logger_service.dart';
import 'package:lockdown_engine/services/anticheat/focus_monitor_service.dart';
import 'package:lockdown_engine/services/anticheat/process_monitor_service.dart';
import 'package:lockdown_engine/services/anticheat/display_monitor_service.dart';
import 'package:lockdown_engine/services/anticheat/screenshot_service.dart';
import 'package:lockdown_engine/core/constants/event_types.dart';

class AntiCheatService extends GetxService {
  late SecurityLoggerService securityLogger;
  late FocusMonitorService focusMonitor;
  late ProcessMonitorService processMonitor;
  late DisplayMonitorService displayMonitor;
  late ScreenshotService screenshotService;
  
  final isMonitoring = false.obs;
  String? _currentSessionId;
  
  @override
  void onInit() {
    super.onInit();
    _initializeServices();
  }
  
  void _initializeServices() {
    securityLogger = Get.put(SecurityLoggerService());
    focusMonitor = Get.put(FocusMonitorService());
    processMonitor = Get.put(ProcessMonitorService());
    displayMonitor = Get.put(DisplayMonitorService());
    screenshotService = Get.put(ScreenshotService());
  }
  
  Future<void> startMonitoring(String sessionId) async {
    if (isMonitoring.value) {
      print('⚠ AntiCheat already monitoring');
      return;
    }
    
    _currentSessionId = sessionId;
    
    // Start all monitoring services
    securityLogger.startLogging(sessionId);
    screenshotService.setSessionId(sessionId);
    focusMonitor.startMonitoring();
    if (Platform.isWindows) {
      processMonitor.startMonitoring();
      displayMonitor.startMonitoring();
    }
    
    // Log exam started event
    securityLogger.logEvent(
      type: EventTypes.EXAM_STARTED,
      data: {
        'session_id': sessionId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    
    isMonitoring.value = true;
    print('✓ AntiCheat monitoring started for session: $sessionId');
  }
  
  Future<void> stopMonitoring() async {
    if (!isMonitoring.value) {
      print('⚠ AntiCheat not monitoring');
      return;
    }
    
    // Log exam finished event
    securityLogger.logEvent(
      type: EventTypes.EXAM_FINISHED,
      data: {
        'session_id': _currentSessionId,
        'timestamp': DateTime.now().toIso8601String(),
        'focus_loss_count': focusMonitor.getFocusLossCount(),
      },
    );
    
    // Stop all monitoring services
    if (Platform.isWindows) {
      displayMonitor.stopMonitoring();
      processMonitor.stopMonitoring();
    }
    focusMonitor.stopMonitoring();
    await securityLogger.stopLogging();
    
    isMonitoring.value = false;
    _currentSessionId = null;
    
    print('✓ AntiCheat monitoring stopped');
  }
  
  // Get monitoring statistics
  Map<String, dynamic> getStatistics() {
    return {
      'is_monitoring': isMonitoring.value,
      'session_id': _currentSessionId,
      'focus_loss_count': focusMonitor.getFocusLossCount(),
      'event_queue_size': securityLogger.getQueueSize(),
    };
  }
  
  @override
  void onClose() {
    if (isMonitoring.value) {
      stopMonitoring();
    }
    super.onClose();
  }
}
