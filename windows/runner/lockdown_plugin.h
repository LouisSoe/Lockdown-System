#ifndef LOCKDOWN_PLUGIN_H_
#define LOCKDOWN_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <commctrl.h>
#include <memory>

namespace lockdown_cbt {

class LockdownPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit LockdownPlugin(flutter::PluginRegistrarWindows* registrar);
  virtual ~LockdownPlugin();

  // Disallow copy and assign.
  LockdownPlugin(const LockdownPlugin&) = delete;
  LockdownPlugin& operator=(const LockdownPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Lockdown methods
  void EnableFullscreen(HWND hwnd);
  void DisableFullscreen(HWND hwnd);
  void BlockShortcuts();
  void UnblockShortcuts();
  void DisableWindowControls(HWND hwnd);
  void EnableWindowControls(HWND hwnd);
  void BlockContextMenu(HWND hwnd);
  void UnblockContextMenu(HWND hwnd);
  void DisableClipboard(HWND hwnd);
  void EnableClipboard(HWND hwnd);
  void EnableKioskMode();
  void DisableKioskMode();
  void PinToAllVirtualDesktops(HWND hwnd);
  void UnpinFromVirtualDesktops(HWND hwnd);
  HWND GetWindowHandle();

  // Keyboard hook
  static LRESULT CALLBACK KeyboardProc(int nCode, WPARAM wParam, LPARAM lParam);

  // Window subclass procedure for context menu + clipboard interception
  static LRESULT CALLBACK SubclassProc(HWND hwnd, UINT msg, WPARAM wParam,
                                        LPARAM lParam, UINT_PTR uIdSubclass,
                                        DWORD_PTR dwRefData);

  // Static members for hooks
  static HHOOK keyboard_hook_;
  static bool is_blocking_;

  flutter::PluginRegistrarWindows* registrar_;
  HWND window_handle_;
  LONG original_style_;
  LONG original_ex_style_;
  WINDOWPLACEMENT original_placement_;

  // Context menu blocking
  bool context_menu_blocked_;
  bool subclass_installed_;

  // Clipboard monitoring
  bool clipboard_blocked_;
};

}  // namespace lockdown_cbt

#endif  // LOCKDOWN_PLUGIN_H_
