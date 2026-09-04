import 'package:flutter/services.dart';
import 'package:get/get.dart';

class LockdownService extends GetxService {
  static const MethodChannel _channel = MethodChannel('lockdown_channel');
  
  final isLocked = false.obs;
  final lockdownStatus = <String, bool>{}.obs;
  
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
  }
  
  // Enable full lockdown
  Future<void> enableLockdown() async {
    try {
      await enableFullscreen();
      await blockShortcuts();
      await disableWindowControls();
      await blockContextMenu();
      await disableClipboard();
      await enableKioskMode();
      
      isLocked.value = true;
      print('✓ Lockdown enabled successfully');
    } catch (e) {
      print('✗ Lockdown error: $e');
      rethrow;
    }
  }
  
  // Disable full lockdown
  Future<void> disableLockdown() async {
    try {
      await disableKioskMode();
      await enableClipboard();
      await unblockContextMenu();
      await enableWindowControls();
      await unblockShortcuts();
      await disableFullscreen();
      
      isLocked.value = false;
      print('✓ Lockdown disabled successfully');
    } catch (e) {
      print('✗ Unlock error: $e');
      rethrow;
    }
  }
  
  // Individual lockdown features
  Future<void> enableFullscreen() async {
    try {
      await _channel.invokeMethod('enableFullscreen');
      lockdownStatus['fullscreen'] = true;
      print('✓ Fullscreen enabled');
    } catch (e) {
      print('✗ Enable fullscreen error: $e');
    }
  }
  
  Future<void> disableFullscreen() async {
    try {
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
}
