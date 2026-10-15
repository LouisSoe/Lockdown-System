import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/modules/exam/controllers/exam_controller.dart';
import 'package:lockdown_engine/services/screen_share/frame_capture_service.dart';
import 'package:lockdown_engine/services/screen_share/screen_share_service.dart';
import 'package:lockdown_engine/modules/exam/views/wifi_dialog.dart';

class ExamView extends GetView<ExamController> {
  const ExamView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final frameCaptureService = Get.find<FrameCaptureService>();

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): () {
          controller.showForceCloseConfirmationDialog();
        },
      },
      child: Focus(
        autofocus: true,
        child: WillPopScope(
          onWillPop: () async {
            controller.showExitDialog();
            return false;
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Column(
              children: [
                _buildStatusBar(context),
                Expanded(
                  // Bungkus seluruh area exam dengan RepaintBoundary
                  // agar FrameCaptureService bisa capture frame via captureKey
                  child: frameCaptureService.wrapWithCapture(
                    Stack(
                      children: [
                        InAppWebView(
                          initialUrlRequest: URLRequest(
                            url: WebUri(controller.examUrl),
                          ),
                          initialSettings:
                              controller.webViewService.getSettings(),
                          onWebViewCreated: controller.onWebViewCreated,
                          onLoadStart:
                              controller.webViewService.handleLoadStart,
                          onLoadStop: controller.webViewService.handleLoadStop,
                          onProgressChanged:
                              controller.webViewService.handleProgressChanged,
                          onLoadError: controller.webViewService.handleLoadError,
                          shouldOverrideUrlLoading:
                              (ctrl, navigationAction) async {
                            controller.webViewService
                                .shouldOverrideUrlLoading(navigationAction);
                            return NavigationActionPolicy.ALLOW;
                          },
                          onDownloadStartRequest: (ctrl, request) {
                            controller.webViewService
                                .handleDownloadStart(request);
                          },
                          onCreateWindow: (ctrl, createWindowAction) async {
                            return controller.webViewService
                                .handleCreateWindow(createWindowAction);
                          },
                          onConsoleMessage: (ctrl, consoleMessage) {
                            controller.webViewService
                                .handleConsoleMessage(consoleMessage);
                          },
                        ),
                        Obx(() => controller.webViewService.isLoading.value
                            ? Container(
                                color: Colors.white,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const CircularProgressIndicator(),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Loading exam...',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Obx(() => LinearProgressIndicator(
                                            value: controller.webViewService
                                                .loadProgress.value,
                                          )),
                                    ],
                                  ),
                                ),
                              )
                            : const SizedBox.shrink()),
                        // Overlay saat gagal memuat halaman / offline
                        Obx(() {
                          if (!controller.webViewService.hasLoadError.value) {
                            return const SizedBox.shrink();
                          }
                          return Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 480),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.red.shade200, width: 2),
                                      ),
                                      child: Icon(Icons.wifi_off_rounded, size: 52, color: Colors.red.shade600),
                                    ),
                                    const SizedBox(height: 18),
                                    const Text(
                                      'Tidak Dapat Memuat Halaman Ujian',
                                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Koneksi internet terputus atau tidak stabil.\nSilakan ganti jaringan Wi-Fi atau muat ulang halaman setelah internet normal.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                                    ),
                                    const SizedBox(height: 22),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.wifi_find_rounded, size: 18),
                                          label: const Text('Ganti Jaringan Wi-Fi', style: TextStyle(fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue.shade700,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: () {
                                            WifiDialog.show(onConnected: () {
                                              controller.webViewService.reload();
                                            });
                                          },
                                        ),
                                        OutlinedButton.icon(
                                          icon: const Icon(Icons.refresh, size: 18),
                                          label: const Text('Coba Muat Ulang'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: () => controller.webViewService.reload(),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    return Container(
      height: 48,
      color: Colors.blue.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Icon gembok dengan Tooltip & info saat diklik
          Tooltip(
            message: 'Mode Lockdown Aktif: Navigasi dan aplikasi lain dibatasi selama ujian.',
            triggerMode: TooltipTriggerMode.tap,
            preferBelow: true,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.lock_rounded, color: Colors.white, size: 20),
              tooltip: 'Mode Lockdown Aktif',
              onPressed: () {
                Get.snackbar(
                  'Mode Lockdown Aktif',
                  'Navigasi dan aplikasi luar dibatasi selama ujian berlangsung.',
                  snackPosition: SnackPosition.TOP,
                  backgroundColor: Colors.black87,
                  colorText: Colors.white,
                  duration: const Duration(seconds: 2),
                  margin: const EdgeInsets.all(12),
                  borderRadius: 8,
                  icon: const Icon(Icons.shield_rounded, color: Colors.blueAccent),
                );
              },
            ),
          ),
          const SizedBox(width: 4),

          // Waktu tersisa di sebelah kunci
          const Icon(Icons.timer_outlined, color: Colors.white70, size: 16),
          const SizedBox(width: 4),
          Obx(() => Text(
                controller.remainingTime.value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              )),

          // Indikator screen share jika aktif
          Obx(() {
            final shareService = Get.find<ScreenShareService>();
            final isConnected =
                shareService.state.value == ScreenShareState.connected;
            if (!isConnected) return const SizedBox.shrink();
            return const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Tooltip(
                message: 'Layar sedang dipantau pengawas',
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(Icons.cast_connected, color: Colors.greenAccent, size: 16),
              ),
            );
          }),

          const Spacer(),

          // Aksi sebelah kanan: Ubah Wi-Fi, Reload, Exit
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.wifi, color: Colors.white, size: 20),
            onPressed: () {
              WifiDialog.show(onConnected: () {
                controller.webViewService.reload();
              });
            },
            tooltip: 'Ganti Wi-Fi / Cek Jaringan',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            onPressed: () => controller.webViewService.reload(),
            tooltip: 'Muat Ulang Halaman (Reload)',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.exit_to_app_rounded, color: Colors.white, size: 20),
            onPressed: controller.showExitDialog,
            tooltip: 'Keluar Ujian',
          ),
        ],
      ),
    );
  }
}
