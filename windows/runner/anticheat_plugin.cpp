#include "anticheat_plugin.h"
#include <tlhelp32.h>
#include <psapi.h>
#include <iostream>

namespace lockdown_cbt {

void AntiCheatPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  if (!registrar) {
    std::cerr << "[AntiCheatPlugin] Error: registrar is null" << std::endl;
    return;
  }

  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "anticheat_channel",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<AntiCheatPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
  std::cout << "[AntiCheatPlugin] Registered successfully with StandardMethodCodec" << std::endl;
}

AntiCheatPlugin::AntiCheatPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

AntiCheatPlugin::~AntiCheatPlugin() {}

void AntiCheatPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();
  std::cout << "[AntiCheatPlugin] Method called: " << method << std::endl;

  if (method == "getRunningProcesses") {
    auto processes = GetRunningProcesses();
    flutter::EncodableList list;
    list.reserve(processes.size());
    for (const auto& proc : processes) {
      list.push_back(flutter::EncodableValue(proc));
    }
    result->Success(flutter::EncodableValue(list));
  } else if (method == "getDisplayCount") {
    int count = GetDisplayCount();
    result->Success(flutter::EncodableValue(count));
  } else if (method == "isRemoteDesktop") {
    bool isRDP = IsRemoteDesktop();
    result->Success(flutter::EncodableValue(isRDP));
  } else {
    result->NotImplemented();
  }
}

std::vector<std::string> AntiCheatPlugin::GetRunningProcesses() {
  std::vector<std::string> processes;

  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

  if (snapshot != INVALID_HANDLE_VALUE) {
    PROCESSENTRY32W pe32;
    pe32.dwSize = sizeof(pe32);

    if (Process32FirstW(snapshot, &pe32)) {
      do {
        std::wstring ws(pe32.szExeFile);
        int size_needed = WideCharToMultiByte(CP_UTF8, 0, ws.c_str(), (int)ws.length(),
                                              NULL, 0, NULL, NULL);
        std::string str(size_needed, 0);
        WideCharToMultiByte(CP_UTF8, 0, ws.c_str(), (int)ws.length(),
                            &str[0], size_needed, NULL, NULL);
        processes.push_back(str);
      } while (Process32NextW(snapshot, &pe32));
    }

    CloseHandle(snapshot);
  }

  return processes;
}

int AntiCheatPlugin::GetDisplayCount() {
  return GetSystemMetrics(SM_CMONITORS);
}

bool AntiCheatPlugin::IsRemoteDesktop() {
  return GetSystemMetrics(SM_REMOTESESSION) != 0;
}

}  // namespace lockdown_cbt
