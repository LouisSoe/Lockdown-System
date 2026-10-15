#ifndef ANTICHEAT_PLUGIN_H_
#define ANTICHEAT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <memory>
#include <string>
#include <vector>

namespace lockdown_cbt {

class AntiCheatPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit AntiCheatPlugin(flutter::PluginRegistrarWindows* registrar);
  virtual ~AntiCheatPlugin();

  // Disallow copy and assign.
  AntiCheatPlugin(const AntiCheatPlugin&) = delete;
  AntiCheatPlugin& operator=(const AntiCheatPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::vector<std::string> GetRunningProcesses();
  int GetDisplayCount();
  bool IsRemoteDesktop();

  flutter::PluginRegistrarWindows* registrar_;
};

}  // namespace lockdown_cbt

#endif  // ANTICHEAT_PLUGIN_H_
