import 'dart:io';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lockdown_engine/kiosk/kiosk_controller.dart';

class LockdownService extends GetxService {
  static const MethodChannel _channel = MethodChannel('lockdown_channel');
  
  final kioskController = KioskController();
  final isLocked = false.obs;
  final lockdownStatus = <String, bool>{}.obs;
  
  // Callback saat terjadi pelanggaran keamanan dari native Android (status bar / home / exit)
  void Function(String reason)? onSecurityViolation;

  // Initialize lockdown status
  @override
  void onInit() {
    super.onInit();
    lockdownStatus.value = {
      'fullscreen': false,
      'shortcuts_blocked': false,
      'window_controls_disabled': false,
      'context_menu_blocked': false,
      'clipboard_disabled': false,
      'kiosk_mode': false,
    };

    // Handler pesan masuk dari native Android (Kotlin)
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSecurityViolation') {
        String reason = 'native_violation';
        if (call.arguments is Map) {
          reason = (call.arguments as Map)['reason']?.toString() ?? 'native_violation';
        }
        print('⚠ Native Security Violation Triggered: $reason');
        onSecurityViolation?.call(reason);
      }
    });
  }
  
  // Enable full lockdown
  Future<void> enableLockdown({
    String? apiBase,
    String? token,
    String? examId,
    String? studentId,
    int? maxViolations,
    bool? hasViolationLimit,
    List<String> allowedPackages = const [],
  }) async {
    final errors = <String>[];

    Future<void> tryStep(String name, Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        errors.add('$name: $e');
        print('✗ Lock step "$name" error: $e');
      }
    }

    if (Platform.isAndroid) {
      await tryStep('kioskStart', () => kioskController.start(
        apiBase: apiBase ?? '',
        token: token ?? '',
        examId: examId ?? '',
        studentId: studentId ?? '',
        maxViolations: maxViolations,
        hasViolationLimit: hasViolationLimit,
        allowedPackages: allowedPackages,
      ));
    }

    await tryStep('enableFullscreen', enableFullscreen);
    await tryStep('setLockState', () => setLockState(true));
    await tryStep('blockShortcuts', blockShortcuts);
    await tryStep('disableWindowControls', disableWindowControls);
    await tryStep('blockContextMenu', blockContextMenu);
    await tryStep('disableClipboard', disableClipboard);
    await tryStep('enableKioskMode', enableKioskMode);
    await tryStep('blockNotifications', blockNotifications);
    await tryStep('addTopOverlay', addTopOverlay);

    isLocked.value = true;
    print('✓ Lockdown enabled successfully (errors: $errors)');
  }
  
  // Disable full lockdown
  Future<void> disableLockdown() async {
    final errors = <String>[];

    Future<void> tryStep(String name, Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        errors.add('$name: $e');
        print('✗ Unlock step "$name" error: $e');
      }
    }

    if (Platform.isAndroid) {
      await tryStep('kioskStop', kioskController.stop);
    }

    await tryStep('removeTopOverlay', removeTopOverlay);         // Lepas lapisan transparan
    await tryStep('setLockState', () => setLockState(false));
    await tryStep('disableFullscreen', disableFullscreen);
    await tryStep('unblockShortcuts', unblockShortcuts);
    await tryStep('enableWindowControls', enableWindowControls);
    await tryStep('unblockContextMenu', unblockContextMenu);
    await tryStep('enableClipboard', enableClipboard);
    await tryStep('disableKioskMode', disableKioskMode);
    await tryStep('unblockNotifications', unblockNotifications);  // Kembalikan notifikasi

    isLocked.value = false;

    if (errors.isEmpty) {
      print('✓ Lockdown disabled successfully');
    } else {
      print('⚠ Lockdown disabled with errors: $errors');
    }
  }
  
  // Individual lockdown features
  Future<void> enableFullscreen() async {
    try {
      if (Platform.isWindows) {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        await windowManager.setFullScreen(true);
      }
      await _channel.invokeMethod('enableFullscreen');
      lockdownStatus['fullscreen'] = true;
      print('✓ Fullscreen enabled');
    } catch (e) {
      print('✗ Enable fullscreen error: $e');
    }
  }
  
  Future<void> disableFullscreen() async {
    try {
      if (Platform.isWindows) {
        await windowManager.setFullScreen(false);
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      }
      await _channel.invokeMethod('disableFullscreen');
      lockdownStatus['fullscreen'] = false;
      print('✓ Fullscreen disabled');
    } catch (e) {
      print('✗ Disable fullscreen error: $e');
    }
  }
  
  Future<void> blockShortcuts() async {
    try {
      await _channel.invokeMethod('blockShortcuts');
      lockdownStatus['shortcuts_blocked'] = true;
      print('✓ Shortcuts blocked');
    } catch (e) {
      print('✗ Block shortcuts error: $e');
    }
  }
  
  Future<void> unblockShortcuts() async {
    try {
      await _channel.invokeMethod('unblockShortcuts');
      lockdownStatus['shortcuts_blocked'] = false;
      print('✓ Shortcuts unblocked');
    } catch (e) {
      print('✗ Unblock shortcuts error: $e');
    }
  }
  
  Future<void> disableWindowControls() async {
    try {
      await _channel.invokeMethod('disableWindowControls');
      lockdownStatus['window_controls_disabled'] = true;
      print('✓ Window controls disabled');
    } catch (e) {
      print('✗ Disable window controls error: $e');
    }
  }
  
  Future<void> enableWindowControls() async {
    try {
      await _channel.invokeMethod('enableWindowControls');
      lockdownStatus['window_controls_disabled'] = false;
      print('✓ Window controls enabled');
    } catch (e) {
      print('✗ Enable window controls error: $e');
    }
  }
  
  Future<void> blockContextMenu() async {
    try {
      await _channel.invokeMethod('blockContextMenu');
      lockdownStatus['context_menu_blocked'] = true;
      print('✓ Context menu blocked');
    } catch (e) {
      print('✗ Block context menu error: $e');
    }
  }
  
  Future<void> unblockContextMenu() async {
    try {
      await _channel.invokeMethod('unblockContextMenu');
      lockdownStatus['context_menu_blocked'] = false;
      print('✓ Context menu unblocked');
    } catch (e) {
      print('✗ Unblock context menu error: $e');
    }
  }
  
  Future<void> disableClipboard() async {
    try {
      await _channel.invokeMethod('disableClipboard');
      lockdownStatus['clipboard_disabled'] = true;
      print('✓ Clipboard disabled');
    } catch (e) {
      print('✗ Disable clipboard error: $e');
    }
  }
  
  Future<void> enableClipboard() async {
    try {
      await _channel.invokeMethod('enableClipboard');
      lockdownStatus['clipboard_disabled'] = false;
      print('✓ Clipboard enabled');
    } catch (e) {
      print('✗ Enable clipboard error: $e');
    }
  }
  
  Future<void> enableKioskMode() async {
    try {
      await _channel.invokeMethod('enableKioskMode');
      lockdownStatus['kiosk_mode'] = true;
      print('✓ Kiosk mode enabled');
    } catch (e) {
      print('✗ Enable kiosk mode error: $e');
    }
  }
  
  Future<void> disableKioskMode() async {
    try {
      await _channel.invokeMethod('disableKioskMode');
      lockdownStatus['kiosk_mode'] = false;
      print('✓ Kiosk mode disabled');
    } catch (e) {
      print('✗ Disable kiosk mode error: $e');
    }
  }

  // ---------------------------------------------------------------
  // Notification Blocking
  // ---------------------------------------------------------------

  /// Blokir semua notifikasi (DND: INTERRUPTION_FILTER_NONE).
  /// Hanya berjalan jika izin ACCESS_NOTIFICATION_POLICY sudah diberikan.
  Future<void> blockNotifications() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('blockNotifications');
        lockdownStatus['notifications_blocked'] = true;
        print('✓ Notifications blocked');
      }
    } catch (e) {
      print('✗ Block notifications error: $e');
    }
  }

  /// Kembalikan filter notifikasi ke kondisi sebelum ujian.
  Future<void> unblockNotifications() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('unblockNotifications');
        lockdownStatus['notifications_blocked'] = false;
        print('✓ Notifications unblocked');
      }
    } catch (e) {
      print('✗ Unblock notifications error: $e');
    }
  }

  /// Cek apakah izin Notification Policy sudah diberikan oleh user.
  /// Kembalikan true jika sudah, false jika belum (perlu buka pengaturan).
  Future<bool> isNotificationPolicyGranted() async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod<bool>('isNotificationPolicyGranted');
        return result ?? false;
      }
      return true; // Platform lain tidak perlu
    } catch (e) {
      print('✗ Check notification policy error: $e');
      return false;
    }
  }

  /// Buka halaman pengaturan izin DND/Notification Policy di Settings Android.
  Future<void> openNotificationPolicySettings() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('openNotificationPolicySettings');
      }
    } catch (e) {
      print('✗ Open notification policy settings error: $e');
    }
  }

  // ---------------------------------------------------------------
  // Transparent Touch Overlay (Penelan Swipe Status Bar)
  // ---------------------------------------------------------------

  /// Pasang lapisan sentuh transparan di atas layar
  Future<void> addTopOverlay() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('addTopOverlay');
        lockdownStatus['top_overlay'] = true;
        print('✓ Top overlay enabled');
      }
    } catch (e) {
      print('✗ Add top overlay error: $e');
    }
  }

  /// Lepas lapisan sentuh transparan
  Future<void> removeTopOverlay() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('removeTopOverlay');
        lockdownStatus['top_overlay'] = false;
        print('✓ Top overlay removed');
      }
    } catch (e) {
      print('✗ Remove top overlay error: $e');
    }
  }

  /// Cek apakah izin "Tampilkan di atas aplikasi lain" sudah diberikan
  Future<bool> isOverlayPermissionGranted() async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod<bool>('isOverlayPermissionGranted');
        return result ?? false;
      }
      return true;
    } catch (e) {
      print('✗ Check overlay permission error: $e');
      return false;
    }
  }

  /// Buka halaman pengaturan izin "Tampilkan di atas aplikasi lain"
  Future<void> openOverlaySettings() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('openOverlaySettings');
      }
    } catch (e) {
      print('✗ Open overlay settings error: $e');
    }
  }

  /// Sinkronisasi status aktif lockdown ke native Android
  Future<void> setLockState(bool locked) async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('setLockState', {'locked': locked});
      }
    } catch (e) {
      print('✗ Set lock state error: $e');
    }
  }

  Future<void> pinToAllVirtualDesktops() async {
    try {
      await _channel.invokeMethod('pinToAllVirtualDesktops');
      print('✓ Pinned to all virtual desktops');
    } catch (e) {
      print('✗ Pin to all virtual desktops error: $e');
    }
  }

  Future<void> unpinFromVirtualDesktops() async {
    try {
      await _channel.invokeMethod('unpinFromVirtualDesktops');
      print('✓ Unpinned from virtual desktops');
    } catch (e) {
      print('✗ Unpin from virtual desktops error: $e');
    }
  }

  // Query lockdown status
  Future<Map<String, bool>> getLockdownStatus() async {
    return lockdownStatus;
  }
  
  // Intercept window close
  Future<bool> handleWindowClose() async {
    if (isLocked.value) {
      print('⚠ Window close blocked by lockdown');
      return false;
    }
    return true;
  }

  @override
  void onClose() {
    kioskController.dispose();
    super.onClose();
  }
}
