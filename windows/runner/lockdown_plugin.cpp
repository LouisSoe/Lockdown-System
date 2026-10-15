#include "lockdown_plugin.h"
#include <dwmapi.h>
#include <shobjidl.h>
#include <commctrl.h>
#include <iostream>
#include <string>

#pragma comment(lib, "comctl32.lib")

// Definitions for undocumented Windows Virtual Desktop Pinning interfaces
namespace {

MIDL_INTERFACE("372E4BA6-23BE-4329-BE4B-A404CE33B428")
IApplicationView : public IUnknown {
 public:
  virtual HRESULT STDMETHODCALLTYPE SetFocus() = 0;
  virtual HRESULT STDMETHODCALLTYPE SwitchTo() = 0;
  virtual HRESULT STDMETHODCALLTYPE TryInvokeBack(void* callback) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetThumbnailWindow(HWND* hwnd) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetVisibility(int* visibility) = 0;
};

MIDL_INTERFACE("1841C6D7-4F9D-42C0-AF41-8747538F10E5")
IApplicationViewCollection : public IUnknown {
 public:
  virtual HRESULT STDMETHODCALLTYPE GetViews(IObjectArray** views) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetViewsByZOrder(IObjectArray** views) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetViewsByAppUserModelId(void* id, IObjectArray** views) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetViewForHwnd(HWND hwnd, IApplicationView** view) = 0;
};

MIDL_INTERFACE("4CE81583-1E4C-4632-A621-07A53543148F")
IVirtualDesktopPinnedApps : public IUnknown {
 public:
  virtual HRESULT STDMETHODCALLTYPE IsAppIdPinned(LPCWSTR appId, BOOL* isPinned) = 0;
  virtual HRESULT STDMETHODCALLTYPE PinAppID(LPCWSTR appId) = 0;
  virtual HRESULT STDMETHODCALLTYPE UnpinAppID(LPCWSTR appId) = 0;
  virtual HRESULT STDMETHODCALLTYPE IsViewPinned(IApplicationView* view, BOOL* isPinned) = 0;
  virtual HRESULT STDMETHODCALLTYPE PinView(IApplicationView* view) = 0;
  virtual HRESULT STDMETHODCALLTYPE UnpinView(IApplicationView* view) = 0;
};

const CLSID CLSID_ImmersiveShell = {0xC2F03A33, 0x21F5, 0x47FA, {0xB4, 0xBB, 0x15, 0x63, 0x62, 0xA2, 0xF2, 0x39}};
const CLSID CLSID_VirtualDesktopPinnedApps = {0xB5A399E7, 0x1C87, 0x46B8, {0x88, 0xE9, 0xFC, 0x57, 0x47, 0xB1, 0x71, 0xBD}};
const IID IID_IApplicationViewCollection = __uuidof(IApplicationViewCollection);
const IID IID_IVirtualDesktopPinnedApps = __uuidof(IVirtualDesktopPinnedApps);

}  // namespace

namespace lockdown_cbt {

// Static member initialization
HHOOK LockdownPlugin::keyboard_hook_ = nullptr;
bool LockdownPlugin::is_blocking_ = false;

// Subclass ID untuk context menu + clipboard interception
static const UINT_PTR kSubclassId = 0xC0DE1234;

// Global pointer ke instance plugin untuk diakses dari SubclassProc
static LockdownPlugin* g_plugin_instance = nullptr;

void LockdownPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  if (!registrar) {
    std::cerr << "[LockdownPlugin] Error: registrar is null" << std::endl;
    return;
  }

  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "lockdown_channel",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<LockdownPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
  std::cout << "[LockdownPlugin] Registered successfully with StandardMethodCodec" << std::endl;
}

LockdownPlugin::LockdownPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar),
      window_handle_(nullptr),
      original_style_(0),
      original_ex_style_(0),
      context_menu_blocked_(false),
      subclass_installed_(false),
      clipboard_blocked_(false) {
  ZeroMemory(&original_placement_, sizeof(WINDOWPLACEMENT));
  g_plugin_instance = this;
}

LockdownPlugin::~LockdownPlugin() {
  if (keyboard_hook_) {
    UnhookWindowsHookEx(keyboard_hook_);
    keyboard_hook_ = nullptr;
  }
  // Hapus subclass saat destroy
  HWND hwnd = GetWindowHandle();
  if (hwnd && subclass_installed_) {
    RemoveWindowSubclass(hwnd, SubclassProc, kSubclassId);
    subclass_installed_ = false;
  }
  // Lepas clipboard listener
  if (hwnd && clipboard_blocked_) {
    RemoveClipboardFormatListener(hwnd);
  }
  g_plugin_instance = nullptr;
}

HWND LockdownPlugin::GetWindowHandle() {
  if (window_handle_ && IsWindow(window_handle_)) {
    return window_handle_;
  }
  HWND hwnd = nullptr;
  if (registrar_ && registrar_->GetView()) {
    hwnd = registrar_->GetView()->GetNativeWindow();
  }
  if (!hwnd) {
    hwnd = GetActiveWindow();
  }
  if (hwnd) {
    HWND root = GetAncestor(hwnd, GA_ROOT);
    if (root) {
      hwnd = root;
    }
  }
  window_handle_ = hwnd;
  return window_handle_;
}

void LockdownPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();
  std::cout << "[LockdownPlugin] Method called: " << method << std::endl;

  HWND hwnd = GetWindowHandle();

  if (method == "enableFullscreen") {
    EnableFullscreen(hwnd);
    result->Success();
  } else if (method == "disableFullscreen") {
    DisableFullscreen(hwnd);
    result->Success();
  } else if (method == "blockShortcuts") {
    BlockShortcuts();
    result->Success();
  } else if (method == "unblockShortcuts") {
    UnblockShortcuts();
    result->Success();
  } else if (method == "disableWindowControls") {
    DisableWindowControls(hwnd);
    result->Success();
  } else if (method == "enableWindowControls") {
    EnableWindowControls(hwnd);
    result->Success();
  } else if (method == "blockContextMenu") {
    BlockContextMenu(hwnd);
    result->Success();
  } else if (method == "unblockContextMenu") {
    UnblockContextMenu(hwnd);
    result->Success();
  } else if (method == "disableClipboard") {
    DisableClipboard(hwnd);
    result->Success();
  } else if (method == "enableClipboard") {
    EnableClipboard(hwnd);
    result->Success();
  } else if (method == "enableKioskMode") {
    EnableKioskMode();
    result->Success();
  } else if (method == "disableKioskMode") {
    DisableKioskMode();
    result->Success();
  } else if (method == "pinToAllVirtualDesktops") {
    PinToAllVirtualDesktops(hwnd);
    result->Success();
  } else if (method == "unpinFromVirtualDesktops") {
    UnpinFromVirtualDesktops(hwnd);
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void LockdownPlugin::EnableFullscreen(HWND hwnd) {
  if (!hwnd) return;
  window_handle_ = hwnd;
  original_style_ = GetWindowLong(hwnd, GWL_STYLE);
  original_ex_style_ = GetWindowLong(hwnd, GWL_EXSTYLE);
  original_placement_.length = sizeof(WINDOWPLACEMENT);
  GetWindowPlacement(hwnd, &original_placement_);
  SetWindowLong(hwnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
  SetWindowLong(hwnd, GWL_EXSTYLE, WS_EX_APPWINDOW | WS_EX_TOPMOST);
  int width = GetSystemMetrics(SM_CXSCREEN);
  int height = GetSystemMetrics(SM_CYSCREEN);
  SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, width, height, SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  SetForegroundWindow(hwnd);
  
  // Pin window to all virtual desktops
  PinToAllVirtualDesktops(hwnd);

  std::cout << "Fullscreen enabled" << std::endl;
}

void LockdownPlugin::DisableFullscreen(HWND hwnd) {
  if (!hwnd) return;

  // Unpin window from virtual desktops
  UnpinFromVirtualDesktops(hwnd);

  SetWindowLong(hwnd, GWL_STYLE, original_style_);
  SetWindowLong(hwnd, GWL_EXSTYLE, original_ex_style_);
  SetWindowPlacement(hwnd, &original_placement_);
  SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  std::cout << "Fullscreen disabled" << std::endl;
}

void LockdownPlugin::BlockShortcuts() {
  if (keyboard_hook_) return;
  keyboard_hook_ = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardProc, NULL, 0);
  is_blocking_ = true;
  std::cout << "Shortcuts blocked" << std::endl;
}

void LockdownPlugin::UnblockShortcuts() {
  if (keyboard_hook_) {
    UnhookWindowsHookEx(keyboard_hook_);
    keyboard_hook_ = nullptr;
  }
  is_blocking_ = false;
  std::cout << "Shortcuts unblocked" << std::endl;
}

LRESULT CALLBACK LockdownPlugin::KeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode >= 0 && is_blocking_) {
    KBDLLHOOKSTRUCT* kbStruct = (KBDLLHOOKSTRUCT*)lParam;
    DWORD vkCode = kbStruct->vkCode;

    if (vkCode == VK_LWIN || vkCode == VK_RWIN) return 1;
    if (vkCode == VK_TAB && (GetAsyncKeyState(VK_MENU) & 0x8000)) return 1;
    if (vkCode == VK_F4 && (GetAsyncKeyState(VK_MENU) & 0x8000)) return 1;
    if (vkCode == VK_ESCAPE && (GetAsyncKeyState(VK_MENU) & 0x8000)) return 1;
    if (vkCode == VK_ESCAPE && (GetAsyncKeyState(VK_CONTROL) & 0x8000) &&
        (GetAsyncKeyState(VK_SHIFT) & 0x8000)) return 1;
    if (vkCode == VK_DELETE && (GetAsyncKeyState(VK_CONTROL) & 0x8000) &&
        (GetAsyncKeyState(VK_MENU) & 0x8000)) return 1;
    if (vkCode == 'D' && ((GetAsyncKeyState(VK_LWIN) & 0x8000) ||
        (GetAsyncKeyState(VK_RWIN) & 0x8000))) return 1;
    if (vkCode == 'L' && ((GetAsyncKeyState(VK_LWIN) & 0x8000) ||
        (GetAsyncKeyState(VK_RWIN) & 0x8000))) return 1;
    if (vkCode == VK_TAB && ((GetAsyncKeyState(VK_LWIN) & 0x8000) ||
        (GetAsyncKeyState(VK_RWIN) & 0x8000))) return 1;
    // Block 3 & 4 finger gesture keystrokes (Win + Ctrl + Left/Right/D/F4 and Win + Up/Down/Left/Right)
    if ((vkCode == VK_LEFT || vkCode == VK_RIGHT || vkCode == 'D' || vkCode == VK_F4) &&
        ((GetAsyncKeyState(VK_LWIN) & 0x8000) || (GetAsyncKeyState(VK_RWIN) & 0x8000)) &&
        (GetAsyncKeyState(VK_CONTROL) & 0x8000)) {
      return 1;
    }
    if ((vkCode == VK_LEFT || vkCode == VK_RIGHT || vkCode == VK_UP || vkCode == VK_DOWN) &&
        ((GetAsyncKeyState(VK_LWIN) & 0x8000) || (GetAsyncKeyState(VK_RWIN) & 0x8000))) {
      return 1;
    }
  }
  return CallNextHookEx(keyboard_hook_, nCode, wParam, lParam);
}

void LockdownPlugin::DisableWindowControls(HWND hwnd) {
  if (!hwnd) return;
  HMENU hMenu = GetSystemMenu(hwnd, FALSE);
  if (hMenu) {
    EnableMenuItem(hMenu, SC_CLOSE, MF_BYCOMMAND | MF_DISABLED | MF_GRAYED);
    EnableMenuItem(hMenu, SC_MINIMIZE, MF_BYCOMMAND | MF_DISABLED | MF_GRAYED);
    EnableMenuItem(hMenu, SC_MAXIMIZE, MF_BYCOMMAND | MF_DISABLED | MF_GRAYED);
  }
  std::cout << "Window controls disabled" << std::endl;
}

void LockdownPlugin::EnableWindowControls(HWND hwnd) {
  if (!hwnd) return;
  GetSystemMenu(hwnd, TRUE);
  std::cout << "Window controls enabled" << std::endl;
}

void LockdownPlugin::BlockContextMenu(HWND hwnd) {
  if (!hwnd) return;
  context_menu_blocked_ = true;

  // Install window subclass jika belum ada
  if (!subclass_installed_) {
    if (SetWindowSubclass(hwnd, SubclassProc, kSubclassId,
                          reinterpret_cast<DWORD_PTR>(this))) {
      subclass_installed_ = true;
      std::cout << "[LockdownPlugin] Subclass installed for context menu blocking" << std::endl;
    } else {
      std::cerr << "[LockdownPlugin] Failed to install subclass" << std::endl;
    }
  }
  std::cout << "[LockdownPlugin] Context menu blocked" << std::endl;
}

void LockdownPlugin::UnblockContextMenu(HWND hwnd) {
  context_menu_blocked_ = false;

  // Hapus subclass hanya jika clipboard juga tidak butuh subclass
  if (subclass_installed_ && !clipboard_blocked_) {
    if (hwnd) {
      RemoveWindowSubclass(hwnd, SubclassProc, kSubclassId);
    }
    subclass_installed_ = false;
  }
  std::cout << "[LockdownPlugin] Context menu unblocked" << std::endl;
}

void LockdownPlugin::DisableClipboard(HWND hwnd) {
  if (!hwnd) return;
  clipboard_blocked_ = true;

  // Install subclass untuk intercept WM_CLIPBOARDUPDATE
  if (!subclass_installed_) {
    if (SetWindowSubclass(hwnd, SubclassProc, kSubclassId,
                          reinterpret_cast<DWORD_PTR>(this))) {
      subclass_installed_ = true;
      std::cout << "[LockdownPlugin] Subclass installed for clipboard blocking" << std::endl;
    }
  }

  // Daftar sebagai clipboard listener — setiap kali clipboard berubah,
  // WM_CLIPBOARDUPDATE akan dikirim ke window kita
  AddClipboardFormatListener(hwnd);

  // Kosongkan clipboard saat ini
  if (OpenClipboard(NULL)) {
    EmptyClipboard();
    CloseClipboard();
  }
  std::cout << "[LockdownPlugin] Clipboard disabled (persistent)" << std::endl;
}

void LockdownPlugin::EnableClipboard(HWND hwnd) {
  clipboard_blocked_ = false;

  // Lepas clipboard listener
  if (hwnd) {
    RemoveClipboardFormatListener(hwnd);
  }

  // Hapus subclass hanya jika context menu juga tidak butuh subclass
  if (subclass_installed_ && !context_menu_blocked_) {
    if (hwnd) {
      RemoveWindowSubclass(hwnd, SubclassProc, kSubclassId);
    }
    subclass_installed_ = false;
  }
  std::cout << "[LockdownPlugin] Clipboard enabled" << std::endl;
}

// SubclassProc — intercept WM_CONTEXTMENU dan WM_CLIPBOARDUPDATE
LRESULT CALLBACK LockdownPlugin::SubclassProc(HWND hwnd, UINT msg,
                                               WPARAM wParam, LPARAM lParam,
                                               UINT_PTR uIdSubclass,
                                               DWORD_PTR dwRefData) {
  LockdownPlugin* self = reinterpret_cast<LockdownPlugin*>(dwRefData);
  if (!self) {
    return DefSubclassProc(hwnd, msg, wParam, lParam);
  }

  switch (msg) {
    case WM_CONTEXTMENU:
      if (self->context_menu_blocked_) {
        // Telan message — context menu tidak akan muncul
        return 0;
      }
      break;

    case WM_CLIPBOARDUPDATE:
      if (self->clipboard_blocked_) {
        // Kosongkan clipboard setiap kali ada perubahan (Ctrl+C dll)
        if (OpenClipboard(NULL)) {
          EmptyClipboard();
          CloseClipboard();
        }
        return 0;
      }
      break;

    case WM_DESTROY:
      // Pastikan subclass dilepas saat window dihancurkan
      RemoveWindowSubclass(hwnd, SubclassProc, uIdSubclass);
      if (self) {
        self->subclass_installed_ = false;
      }
      break;
  }

  return DefSubclassProc(hwnd, msg, wParam, lParam);
}

void LockdownPlugin::EnableKioskMode() {
  HKEY hKey;
  LONG res = RegCreateKeyEx(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System",
      0, NULL, REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &hKey, NULL);
  if (res == ERROR_SUCCESS) {
    DWORD value = 1;
    RegSetValueEx(hKey, L"DisableTaskMgr", 0, REG_DWORD, (BYTE*)&value, sizeof(value));
    RegCloseKey(hKey);
  }
  std::cout << "Kiosk mode enabled" << std::endl;
}

void LockdownPlugin::DisableKioskMode() {
  HKEY hKey;
  LONG res = RegOpenKeyEx(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System",
      0, KEY_WRITE, &hKey);
  if (res == ERROR_SUCCESS) {
    RegDeleteValue(hKey, L"DisableTaskMgr");
    RegCloseKey(hKey);
  }
  std::cout << "Kiosk mode disabled" << std::endl;
}

void LockdownPlugin::PinToAllVirtualDesktops(HWND hwnd) {
  if (!hwnd) return;

  IServiceProvider* service_provider = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_ImmersiveShell, nullptr, CLSCTX_LOCAL_SERVER,
                                IID_PPV_ARGS(&service_provider));
  if (FAILED(hr) || !service_provider) {
    std::cerr << "[LockdownPlugin] Failed to create ImmersiveShell instance: 0x"
              << std::hex << hr << std::dec << std::endl;
    return;
  }

  IApplicationViewCollection* view_collection = nullptr;
  hr = service_provider->QueryService(IID_IApplicationViewCollection,
                                      IID_PPV_ARGS(&view_collection));
  if (SUCCEEDED(hr) && view_collection) {
    IApplicationView* app_view = nullptr;
    hr = view_collection->GetViewForHwnd(hwnd, &app_view);
    if (SUCCEEDED(hr) && app_view) {
      IVirtualDesktopPinnedApps* pinned_apps = nullptr;
      hr = service_provider->QueryService(CLSID_VirtualDesktopPinnedApps,
                                          IID_PPV_ARGS(&pinned_apps));
      if (SUCCEEDED(hr) && pinned_apps) {
        BOOL is_pinned = FALSE;
        hr = pinned_apps->IsViewPinned(app_view, &is_pinned);
        if (SUCCEEDED(hr) && !is_pinned) {
          hr = pinned_apps->PinView(app_view);
          if (SUCCEEDED(hr)) {
            std::cout << "[LockdownPlugin] Window pinned to all virtual desktops successfully!" << std::endl;
          } else {
            std::cerr << "[LockdownPlugin] PinView failed: 0x" << std::hex << hr << std::dec << std::endl;
          }
        } else if (is_pinned) {
          std::cout << "[LockdownPlugin] Window is already pinned to all virtual desktops" << std::endl;
        }
        pinned_apps->Release();
      } else {
        std::cerr << "[LockdownPlugin] Failed to query IVirtualDesktopPinnedApps: 0x"
                  << std::hex << hr << std::dec << std::endl;
      }
      app_view->Release();
    } else {
      std::cerr << "[LockdownPlugin] GetViewForHwnd failed: 0x"
                << std::hex << hr << std::dec << std::endl;
    }
    view_collection->Release();
  } else {
    std::cerr << "[LockdownPlugin] Failed to query IApplicationViewCollection: 0x"
              << std::hex << hr << std::dec << std::endl;
  }
  service_provider->Release();
}

void LockdownPlugin::UnpinFromVirtualDesktops(HWND hwnd) {
  if (!hwnd) return;

  IServiceProvider* service_provider = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_ImmersiveShell, nullptr, CLSCTX_LOCAL_SERVER,
                                IID_PPV_ARGS(&service_provider));
  if (FAILED(hr) || !service_provider) return;

  IApplicationViewCollection* view_collection = nullptr;
  hr = service_provider->QueryService(IID_IApplicationViewCollection,
                                      IID_PPV_ARGS(&view_collection));
  if (SUCCEEDED(hr) && view_collection) {
    IApplicationView* app_view = nullptr;
    hr = view_collection->GetViewForHwnd(hwnd, &app_view);
    if (SUCCEEDED(hr) && app_view) {
      IVirtualDesktopPinnedApps* pinned_apps = nullptr;
      hr = service_provider->QueryService(CLSID_VirtualDesktopPinnedApps,
                                          IID_PPV_ARGS(&pinned_apps));
      if (SUCCEEDED(hr) && pinned_apps) {
        BOOL is_pinned = FALSE;
        hr = pinned_apps->IsViewPinned(app_view, &is_pinned);
        if (SUCCEEDED(hr) && is_pinned) {
          pinned_apps->UnpinView(app_view);
          std::cout << "[LockdownPlugin] Window unpinned from virtual desktops" << std::endl;
        }
        pinned_apps->Release();
      }
      app_view->Release();
    }
    view_collection->Release();
  }
  service_provider->Release();
}

}  // namespace lockdown_cbt
