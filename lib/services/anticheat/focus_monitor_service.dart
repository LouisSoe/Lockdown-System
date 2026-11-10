import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/core/constants/event_types.dart';
import 'package:lockdown_engine/services/anticheat/security_logger_service.dart';

class FocusMonitorService extends GetxService with WidgetsBindingObserver {
  SecurityLoggerService? _securityLogger;
  int focusLossCount = 0;
  bool _isMonitoring = false;
  bool _hasLostFocus = false;
  
  DateTime? _graceUntil;
  
  // Callbacks for strict CBT policy and listeners
  void Function(int count)? onFocusLost;
  void Function(int count)? onFocusRegained;
  
  void startMonitoring({int gracePeriodSeconds = 10}) {
    if (_isMonitoring) return;
    
    try {
      _securityLogger = Get.find<SecurityLoggerService>();
    } catch (_) {}
    
    _graceUntil = DateTime.now().add(Duration(seconds: gracePeriodSeconds));
    WidgetsBinding.instance.addObserver(this);
    _isMonitoring = true;
    _hasLostFocus = false;
    focusLossCount = 0;
    
    print('✓ Focus monitoring started with ${gracePeriodSeconds}s initial grace period');
  }

  void extendGracePeriod({int seconds = 10}) {
    _graceUntil = DateTime.now().add(Duration(seconds: seconds));
    _hasLostFocus = false;
    print('✓ Focus grace period extended for ${seconds}s');
  }

  void endGracePeriod() {
    _graceUntil = null;
    print('✓ Focus grace period ended');
  }

  bool get isInGracePeriod =>
      _graceUntil != null && DateTime.now().isBefore(_graceUntil!);
  
  void stopMonitoring() {
    if (!_isMonitoring) return;
    
    WidgetsBinding.instance.removeObserver(this);
    _isMonitoring = false;
    _securityLogger = null;
    _hasLostFocus = false;
    _graceUntil = null;
    onFocusLost = null;
    onFocusRegained = null;
    
    print('✓ Focus monitoring stopped');
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isMonitoring) return;
    
    // Abaikan perubahan siklus hidup selama grace period awal (transisi navbar / popup pin sistem)
    if (isInGracePeriod) {
      if (state == AppLifecycleState.resumed) {
        _hasLostFocus = false;
      }
      print('ℹ Mengabaikan event lifecycle ($state) karena masih dalam masa persiapan ujian');
      return;
    }

    // Saat aplikasi kehilangan fokus (minimize / buka aplikasi lain / status bar)
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      if (!_hasLostFocus) {
        _hasLostFocus = true;
        focusLossCount++;
        
        _securityLogger?.logEvent(
          type: EventTypes.FOCUS_LOST,
          data: {
            'count': focusLossCount,
            'state': state.toString(),
            'timestamp': DateTime.now().toIso8601String(),
          },
          captureScreenshot: false,
        );
        
        print('⚠ Focus lost detected (Count: $focusLossCount)');
        onFocusLost?.call(focusLossCount);
      }
    } else if (state == AppLifecycleState.resumed) {
      // Saat siswa kembali membuka aplikasi ujian
      final hadFocusLoss = _hasLostFocus;
      _hasLostFocus = false;

      _securityLogger?.logEvent(
        type: EventTypes.FOCUS_GAINED,
        data: {
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (hadFocusLoss) {
        print('✓ Focus regained detected (Count: $focusLossCount)');
        onFocusRegained?.call(focusLossCount);
      }
    }
  }

  int _lastViolationTime = 0;

  /// Rekam pelanggaran fokus langsung dari trigger native (Status bar / Home / Keluar app)
  void recordViolation({String reason = 'system_focus_lost'}) {
    if (!_isMonitoring) return;

    if (isInGracePeriod) {
      print('ℹ Mengabaikan pelanggaran native ($reason) selama masa persiapan awal ujian');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    // Debounce 1.5 detik untuk menghindari pelaporan ganda dari event beruntun
    if (now - _lastViolationTime < 1500) {
      return;
    }
    _lastViolationTime = now;

    focusLossCount++;
    _hasLostFocus = true;

    _securityLogger?.logEvent(
      type: EventTypes.FOCUS_LOST,
      data: {
        'count': focusLossCount,
        'state': reason,
        'timestamp': DateTime.now().toIso8601String(),
      },
      captureScreenshot: false,
    );

    print('⚠ Violation recorded via Native Trigger ($reason, Count: $focusLossCount)');
    onFocusLost?.call(focusLossCount);
  }
  
  int getFocusLossCount() => focusLossCount;

  void resetFocusLossCount() {
    focusLossCount = 0;
    _hasLostFocus = false;
    _lastViolationTime = 0;
  }

  void setFocusLossCount(int count) {
    focusLossCount = count;
    _hasLostFocus = false;
    _lastViolationTime = 0;
  }
  
  @override
  void onClose() {
    stopMonitoring();
    super.onClose();
  }
}
