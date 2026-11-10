import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/core/constants/event_types.dart';
import 'package:lockdown_engine/core/config/app_config.dart';
import 'package:lockdown_engine/services/anticheat/security_logger_service.dart';

class ProcessMonitorService extends GetxService {
  static const MethodChannel _channel = MethodChannel('anticheat_channel');
  
  SecurityLoggerService? _securityLogger;
  Timer? _monitorTimer;
  bool _isMonitoring = false;
  
  // Blacklisted processes (will be detected as violations)
  final blacklistedProcesses = [
    // Browsers
    'chrome.exe', 'firefox.exe', 'brave.exe', 'opera.exe', 
    'edge.exe', 'msedge.exe', 'safari.exe',
    
    // Remote access
    'teamviewer.exe', 'anydesk.exe', 'ammyy.exe',
    
    // Virtual machines
    'vmware.exe', 'virtualbox.exe', 'vboxsvc.exe',
    
    // Communication apps
    'discord.exe', 'telegram.exe', 'whatsapp.exe', 'skype.exe',
    'zoom.exe', 'teams.exe', 'slack.exe',
    
    // Screen capture
    'obs64.exe', 'obs32.exe', 'streamlabs.exe',
    
    // Developer tools
    'cmd.exe', 'powershell.exe', 'devenv.exe', 'code.exe',
  ];
  
  void startMonitoring() {
    if (!Platform.isWindows) {
      print('ℹ Process monitoring skipped on non-Windows platform');
      return;
    }
    if (_isMonitoring) return;
    
    _securityLogger = Get.find<SecurityLoggerService>();
    _isMonitoring = true;
    
    _monitorTimer = Timer.periodic(
      AppConfig.processMonitorInterval,
      (_) => _checkRunningProcesses(),
    );
    
    print('✓ Process monitoring started');
  }
  
  void stopMonitoring() {
    if (!_isMonitoring) return;
    
    _monitorTimer?.cancel();
    _isMonitoring = false;
    _securityLogger = null;
    
    print('✓ Process monitoring stopped');
  }
  
  Future<void> _checkRunningProcesses() async {
    try {
      final result = await _channel.invokeMethod('getRunningProcesses');
      final processes = List<String>.from(result ?? []);
      
      for (var process in processes) {
        final processLower = process.toLowerCase();
        
        if (_isBlacklisted(processLower)) {
          _securityLogger?.logEvent(
            type: EventTypes.PROCESS_VIOLATION,
            data: {
              'process': process,
              'timestamp': DateTime.now().toIso8601String(),
            },
            captureScreenshot: true,
          );
          
          print('⚠ Blacklisted process detected: $process');
        }
      }
    } catch (e) {
      print('✗ Process monitor error: $e');
    }
  }
  
  bool _isBlacklisted(String processName) {
    return blacklistedProcesses.any((p) => processName.contains(p.toLowerCase()));
  }
  
  void addToBlacklist(String processName) {
    blacklistedProcesses.add(processName.toLowerCase());
  }
  
  void removeFromBlacklist(String processName) {
    blacklistedProcesses.remove(processName.toLowerCase());
  }
  
  @override
  void onClose() {
    stopMonitoring();
    super.onClose();
  }
}
